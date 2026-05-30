defmodule Odysseus.Astrocyte do
  @moduledoc """
  Astrocyte — resource caching, rate limiting, and energy buffering.

  Two-tier LRU cache: Rust NIF (fast) with Elixir map fallback.
  Glycogen storage (response cache), blood-brain barrier (rate limiting),
  emergency energy release triggered by hypothalamus.
  """

  use GenServer

  @max_cache_size 1000
  @rate_limit_window_ms 60_000
  @rate_limit_max 100

  defstruct [
    :nif_cache,
    cache: %{},
    rate_counter: %{count: 0, window_start: 0}
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # ─── Public API ──────────────────────────────────────────────

  def cache_get(key), do: GenServer.call(__MODULE__, {:get, key})

  def cache_put(key, value, opts \\ []) do
    emotional_weight = Keyword.get(opts, :emotional_weight, 0.5)
    context = Keyword.get(opts, :context, [])
    GenServer.cast(__MODULE__, {:put, key, value, emotional_weight, context})
  end

  def rate_check(pid), do: GenServer.call(__MODULE__, {:rate_check, pid})
  def flush_cache, do: GenServer.cast(__MODULE__, :flush)

  def release_cache(fraction) do
    GenServer.call(__MODULE__, {:release, fraction})
  end

  def stats, do: GenServer.call(__MODULE__, :stats)

  # ─── GenServer callbacks ─────────────────────────────────────

  @impl true
  def init(_opts) do
    Odysseus.WhiteMatter.subscribe(:astrocyte)

    nif_cache = try do
      Odysseus.Astrocyte.Nif.new_cache(@max_cache_size)
    rescue
      _ -> nil
    end

    {:ok, %__MODULE__{nif_cache: nif_cache}}
  end

  @impl true
  def handle_call({:get, key}, _from, data) do
    now = System.system_time(:millisecond)
    result = nif_get(data.nif_cache, key, now) || Map.get(data.cache, key)
    {:reply, result, data}
  end

  @impl true
  def handle_call({:rate_check, _pid}, _from, data) do
    now = System.system_time(:millisecond)
    counter = if now - data.rate_counter.window_start > @rate_limit_window_ms do
      %{count: 1, window_start: now}
    else
      %{data.rate_counter | count: data.rate_counter.count + 1}
    end
    allowed = counter.count <= @rate_limit_max
    {:reply, allowed, %{data | rate_counter: counter}}
  end

  @impl true
  def handle_call({:release, fraction}, _from, data) do
    released = if data.nif_cache do
      try do
        Odysseus.Astrocyte.Nif.release(data.nif_cache, fraction)
      rescue
        _ -> 0
      end
    else
      # Elixir fallback: remove lowest-weight entries
      elixir_release(data, fraction)
    end
    {:reply, released, data}
  end

  @impl true
  def handle_call(:stats, _from, data) do
    nif_stats = if data.nif_cache do
      try do
        Odysseus.Astrocyte.Nif.stats(data.nif_cache)
      rescue
        _ -> nil
      end
    else
      nil
    end

    result = if nif_stats do
      nif_stats
    else
      %{
        entries: map_size(data.cache),
        capacity: @max_cache_size,
        hits: 0,
        misses: 0,
        hit_rate: 0.0,
        evictions: 0,
        backend: :elixir
      }
    end

    {:reply, result, data}
  end

  @impl true
  def handle_cast({:put, key, value, emotional_weight, context}, data) do
    now = System.system_time(:millisecond)

    # Try NIF cache first
    if data.nif_cache do
      try do
        Odysseus.Astrocyte.Nif.put(data.nif_cache, key, value, emotional_weight, context, now)
      rescue
        _ -> :ok
      end
    end

    # Also store in Elixir fallback
    cache = if map_size(data.cache) >= @max_cache_size do
      [{oldest_key, _} | _] = Map.to_list(data.cache)
      data.cache |> Map.delete(oldest_key) |> Map.put(key, value)
    else
      Map.put(data.cache, key, value)
    end

    {:noreply, %{data | cache: cache}}
  end

  @impl true
  def handle_cast(:flush, data) do
    if data.nif_cache do
      try do
        Odysseus.Astrocyte.Nif.flush(data.nif_cache)
      rescue
        _ -> :ok
      end
    end
    {:noreply, %{data | cache: %{}}}
  end

  # Cache release signal from hypothalamus
  @impl true
  def handle_info(%{type: :cache_release, fraction: fraction}, data) do
    if data.nif_cache do
      try do
        Odysseus.Astrocyte.Nif.release(data.nif_cache, fraction)
      rescue
        _ -> :ok
      end
    end
    {:noreply, data}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ─── Private ─────────────────────────────────────────────────

  defp nif_get(nif_cache, key, now) do
    if nif_cache do
      try do
        case Odysseus.Astrocyte.Nif.get(nif_cache, key, now) do
          nil -> nil
          entry -> Map.get(entry, :content)
        end
      rescue
        _ -> nil
      end
    else
      nil
    end
  end

  defp elixir_release(data, fraction) do
    to_release = max(1, round(map_size(data.cache) * fraction))
    # Remove entries with lowest emotional weight (not tracked in Elixir fallback,
    # so just remove oldest)
    to_drop = data.cache
      |> Map.to_list()
      |> Enum.take(to_release)
      |> Enum.map(fn {k, _} -> k end)

    Enum.each(to_drop, fn k ->
      send(self(), {:cache_evict, k})
    end)

    length(to_drop)
  end
end
