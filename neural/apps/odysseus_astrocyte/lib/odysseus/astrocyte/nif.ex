defmodule Odysseus.Astrocyte.Nif do
  @moduledoc """
  Astrocyte NIF — holds Rust LRU cache resource, processes signals.

  Rust NIF functions (loaded from libodysseus_astrocyte):
    new_cache/1, put/6, get/3, release/2, flush/1, stats/1

  LRU eviction by access order; emotion-weighted release for hypothalamus pressure.
  """

  use GenServer

  @on_load :load_nifs

  defstruct [:cache]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def cache, do: GenServer.call(__MODULE__, :get_cache)

  # ─── NIF Loading ─────────────────────────────────────────────

  def load_nifs do
    case :code.priv_dir(:odysseus_brain) do
      {:error, _} -> :ok
      priv ->
        path = Path.join([to_string(priv), "libodysseus_astrocyte"])
        :erlang.load_nif(String.to_charlist(path), 0)
    end
  end

  # NIF function stubs (replaced when .dylib loads)
  def new_cache(_capacity), do: :erlang.nif_error("astrocyte NIF not loaded")
  def put(_res, _key, _content, _emotional_weight, _context, _now), do: :erlang.nif_error("astrocyte NIF not loaded")
  def get(_res, _key, _now), do: :erlang.nif_error("astrocyte NIF not loaded")
  def release(_res, _fraction), do: :erlang.nif_error("astrocyte NIF not loaded")
  def flush(_res), do: :erlang.nif_error("astrocyte NIF not loaded")
  def stats(_res), do: :erlang.nif_error("astrocyte NIF not loaded")

  # ─── GenServer callbacks ─────────────────────────────────────

  @impl true
  def init(_opts) do
    Odysseus.WhiteMatter.subscribe(:astrocyte)

    cache = try do
      new_cache(1000)
    rescue
      _ -> nil
    end

    {:ok, %__MODULE__{cache: cache}}
  end

  @impl true
  def handle_call(:get_cache, _from, state) do
    {:reply, state.cache, state}
  end

  # Cache release signal from hypothalamus (token budget pressure)
  @impl true
  def handle_info(%{type: :cache_release, fraction: fraction}, state) do
    if state.cache do
      try do
        released = release(state.cache, fraction)
        Odysseus.WhiteMatter.send_signal(:hypothalamus, %{
          type: :cache_released,
          count: released,
          fraction: fraction
        })
      rescue
        _ -> :ok
      end
    end
    {:noreply, state}
  end

  # Flush signal from glymphatic during SLEEP cleanup
  @impl true
  def handle_info(%{type: :flush_cache}, state) do
    if state.cache do
      try do
        flush(state.cache)
      rescue
        _ -> :ok
      end
    end
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}
end
