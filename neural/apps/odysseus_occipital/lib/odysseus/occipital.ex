defmodule Odysseus.Occipital do
  @moduledoc """
  Occipital Lobe — input encoding, feature extraction, preprocessing.

  Converts raw input into structured feature representations.
  Deterministic computation (Rust NIF candidate for heavy encoding).
  """

  use GenServer

  defstruct [
    encoding_stats: %{processed: 0, features_extracted: 0}
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # ─── GenServer callbacks ─────────────────────────────────────

  @impl true
  def init(_opts) do
    Odysseus.WhiteMatter.subscribe(:occipital)
    {:ok, %__MODULE__{}}
  end

  # Handle event signals — encode features
  @impl true
  def handle_info(%{target_lobe: :occipital, content: content, attention_weight: weight}, state) do
    features = extract_features(content)

    # Route encoded features to parietal (attention) and temporal (language)
    if weight > 0.2 do
      Odysseus.WhiteMatter.send_signal(:parietal, %{
        type: :encoded_features,
        features: features,
        source: :occipital
      })

      Odysseus.WhiteMatter.send_signal(:temporal, %{
        type: :encoded_features,
        features: features,
        source: :occipital
      })
    end

    stats = state.encoding_stats
    new_stats = %{processed: stats.processed + 1, features_extracted: stats.features_extracted + length(features)}

    {:noreply, %{state | encoding_stats: new_stats}}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ─── Feature extraction ──────────────────────────────────────

  defp extract_features(content) do
    # Basic deterministic feature extraction.
    # Production: Rust NIF for embedding computation.
    %{
      length: String.length(content),
      word_count: content |> String.split(~r/\s+/, trim: true) |> length(),
      has_code: String.contains?(content, ["```", "def ", "function ", "class ", "import "]),
      has_question: String.contains?(content, "?"),
      has_url: String.contains?(content, ["http://", "https://"]),
      sentiment_hint: simple_sentiment(content)
    }
    |> Map.to_list()
    |> Enum.filter(fn {_k, v} -> v != false and v != nil end)
  end

  defp simple_sentiment(text) do
    positive = String.contains?(text, ["good", "great", "thanks", "perfect", "nice", "love"])
    negative = String.contains?(text, ["bad", "error", "fail", "wrong", "bug", "broken"])

    cond do
      positive and not negative -> :positive
      negative and not positive -> :negative
      true -> nil
    end
  end
end
