defmodule ElixirStatus.Publisher do
  @moduledoc """
    The Publisher comes into play whenever a Posting is made or updated.

    The Publisher is e.g. tasked with promoting postings on Twitter.
  """

  require Logger

  alias ElixirStatus.LinkShortener
  alias ElixirStatus.Posting
  alias ElixirStatus.PostingController

  @direct_message_recipient Application.get_env(:elixir_status, :twitter_dm_recipient)

  @doc """
    Called when a posting is created by PostingController.

    Promotes the posting on Twitter, among other things.
  """
  def after_create(new_posting) do
    new_posting
      |> create_all_short_links
      |> send_direct_message
    tweet_uid = post_to_twitter(new_posting)
    PostingController.update_published_tweet_uid(new_posting, tweet_uid)
  end

  @doc """
    Called when a posting is updated by PostingController.
  """
  def after_update(updated_posting) do
    updated_posting
      |> create_all_short_links
  end

  @doc """
    Returns a permalink consisting of an unmodified UID and a kebap-cased title.

        Publisher.permalink("aB87", "I really like this TiTlE")
        # => "aB87-i-really-like-this-title"
  """
  def permalink(_uid, nil) do
    nil
  end

  def permalink(uid, title) do
    permatitle = Regex.split(~r/\s|\%20/, title)
                  |> Enum.join("-")
                  |> String.downcase
                  |> String.replace(~r/[^a-z0-9\-]/, "")
    "#{uid}-#{permatitle}"
  end


  defp create_all_short_links(posting) do
    text = Earmark.to_html(posting.text)
    Regex.scan(~r/href=\"([^\"]+?)\"/, text)
      |> Enum.map(fn([_, x]) -> LinkShortener.to_uid(x) end)

    posting
  end

  # Sends a direct message via Twitter.
  defp send_direct_message(%Posting{title: title, permalink: permalink}) do
    "#{short_title(title)} #{short_url(permalink)}"
      |> send_on_twitter(Mix.env)
  end

  defp send_on_twitter(text, :prod) do
    ExTwitter.send_direct_message(@direct_message_recipient, text)
  end

  defp send_on_twitter(tweet, _) do
    Logger.debug "send_direct_message: #{tweet}"
    nil
  end

  defp post_to_twitter(posting) do
    posting
      |> tweet_text
      |> update_on_twitter(Mix.env)
  end

  defp update_on_twitter(tweet, :prod) do
    %ExTwitter.Model.Tweet{id_str: uid} = ExTwitter.update(tweet)
    uid
  end

  defp update_on_twitter(tweet, _) do
    Logger.debug "update_twitter_status: #{tweet}"
    nil
  end

  @doc """
    Returns the text for the tweet announcing the given posting.
  """
  def tweet_text(%Posting{title: title, permalink: permalink}) do
    "#{short_title(title)} #{short_url(permalink)} #elixirlang"
  end

  @doc """
    Shortens a given +title+ to +max+ length.
  """
  def short_title(title, max \\ 100, truncate_with \\ "...") do
    if String.length(title) <= max do
      title
    else
      String.slice(title, 0..max-String.length(truncate_with)-1) <> truncate_with
    end
  end

  defp short_url(permalink) do
    uid = "/p/#{permalink}"
            |> ElixirStatus.URL.from_path
            |> LinkShortener.to_uid
    "/=#{uid}"
      |> ElixirStatus.URL.from_path
  end
end
