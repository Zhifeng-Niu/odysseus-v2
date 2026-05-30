defmodule Odysseus.WhiteMatter do
  @moduledoc """
  White Matter — inter-region message routing layer.

  Implements the corpus callosum (left-right brain sync),
  arcuate fasciculus (frontal-temporal), and ascending/descending tracts.
  All inter-structure communication flows through here.
  """

  use GenServer

  defstruct [:subscriptions]

  @type t :: %__MODULE__{subscriptions: %{atom() => [pid()]}}

  # ─── Public API ──────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Subscribe a process to receive messages for a given brain region."
  def subscribe(region) when is_atom(region) do
    GenServer.call(__MODULE__, {:subscribe, region, self()})
  end

  @doc "Send a signal to a specific brain region."
  def send_signal(region, signal) when is_atom(region) do
    GenServer.cast(__MODULE__, {:send, region, signal})
  end

  @doc "Broadcast a signal to all subscribed regions."
  def broadcast(signal) do
    GenServer.cast(__MODULE__, {:broadcast, signal})
  end

  @doc "Send signal to corpus callosum (left-right brain sync)."
  def corpus_callosum(hemisphere, signal) when hemisphere in [:left, :right] do
    target = if hemisphere == :left, do: :frontal_right, else: :frontal_left
    send_signal(target, signal)
  end

  # ─── GenServer callbacks ─────────────────────────────────────

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{subscriptions: %{}}}
  end

  @impl true
  def handle_call({:subscribe, region, pid}, _from, state) do
    refs = state.subscriptions
    subscribers = Map.get(refs, region, [])
    updated = Map.put(refs, region, [pid | subscribers] |> Enum.uniq())
    Process.monitor(pid)
    {:reply, :ok, %{state | subscriptions: updated}}
  end

  @impl true
  def handle_cast({:send, region, signal}, state) do
    deliver(region, signal, state.subscriptions)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:broadcast, signal}, state) do
    for {_region, subscribers} <- state.subscriptions do
      for pid <- subscribers, do: send(pid, signal)
    end
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    cleaned = state.subscriptions
    |> Enum.map(fn {region, subscribers} ->
      {region, List.delete(subscribers, pid)}
    end)
    |> Enum.filter(fn {_, subs} -> subs != [] end)
    |> Map.new()
    {:noreply, %{state | subscriptions: cleaned}}
  end

  defp deliver(region, signal, subscriptions) do
    for pid <- Map.get(subscriptions, region, []) do
      send(pid, signal)
    end
  end
end
