defmodule Odysseus.Brain.Router do
  @moduledoc """
  HTTP API — TypeScript TUI connects to Elixir brain via this Plug router.

  Endpoints:
    GET  /health          — brain health + NIF status
    GET  /status          — full brain status (arousal, state, structures)
    POST /chat            — inject text signal into brainstem
    GET  /structures      — list all brain structures and their status
  """

  use Plug.Router

  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :match
  plug :dispatch

  get "/health" do
    send_json(conn, 200, %{
      status: "running",
      nifs_loaded: nif_status(),
      uptime: elem(:erlang.statistics(:wall_clock), 0) |> div(1000)
    })
  end

  get "/status" do
    brainstem = try do
      Odysseus.Brainstem.status()
    rescue
      _ -> %{}
    end
    hypo_state = try do
      Odysseus.Hypothalamus.state()
    rescue
      _ -> :unknown
    end
    send_json(conn, 200, %{
      brainstem: brainstem,
      hypothalamus: hypo_state,
      structures: structure_count()
    })
  end

  post "/chat" do
    case conn.body_params do
      %{"message" => message} when is_binary(message) ->
        intensity = Map.get(conn.body_params, "intensity", 0.5)
        source = Map.get(conn.body_params, "source", "api")
        Odysseus.Brainstem.inject(
          String.to_atom(source),
          :text,
          message,
          intensity / 1
        )
        Odysseus.Hypothalamus.report_interaction()
        send_json(conn, 200, %{status: "processed", message: message})
      _ ->
        send_json(conn, 400, %{error: "missing 'message' field"})
    end
  end

  post "/enrich" do
    case conn.body_params do
      %{"message" => message} when is_binary(message) ->
        # Emotional evaluation
        emotion = try do
          tag = Odysseus.Amygdala.Nif.evaluate_text(message)
          if tag do
            %{valence: tag.valence, arousal: tag.arousal, urgency: tag.urgency,
              threat: tag.threat, opportunity: tag.opportunity}
          else
            %{valence: 0.0, arousal: 0.3, urgency: 0.1, threat: 0.0, opportunity: 0.1}
          end
        rescue
          _ -> %{valence: 0.0, arousal: 0.3, urgency: 0.1, threat: 0.0, opportunity: 0.1}
        end

        # Feature extraction
        features = %{
          length: String.length(message),
          word_count: message |> String.split(~r/\s+/, trim: true) |> length(),
          has_question: String.contains?(message, "?"),
          has_code: String.contains?(message, ["```", "def ", "function ", "class "])
        }

        # Attention allocation
        attention = try do
          Odysseus.Parietal.attention()
        rescue
          _ -> %{frontal_left: 0.4, frontal_right: 0.2, temporal: 0.2, occipital: 0.2}
        end

        # Determine primary lobe
        primary_lobe = if emotion.valence < -0.2 or features.has_question do
          :frontal_left
        else
          :frontal_right
        end

        send_json(conn, 200, %{
          emotion: emotion,
          features: features,
          attention: attention,
          primary_lobe: primary_lobe,
          intensity: Map.get(conn.body_params, "intensity", 0.5)
        })
      _ ->
        send_json(conn, 400, %{error: "missing 'message' field"})
    end
  end

  get "/structures" do
    send_json(conn, 200, %{
      cortex: ["frontal_left", "frontal_right", "parietal", "temporal", "occipital"],
      limbic: ["amygdala", "hippocampus"],
      subcortical: ["basal_ganglia", "cerebellum"],
      brainstem: ["brainstem"],
      support: ["white_matter", "hypothalamus", "astrocyte", "glymphatic", "neurons"]
    })
  end

  match _ do
    send_json(conn, 404, %{error: "not found"})
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  defp nif_status do
    %{
      neurons: nif_loaded?(Odysseus.Neurons.Nif),
      hippocampus: nif_loaded?(Odysseus.Hippocampus.Nif),
      amygdala: nif_loaded?(Odysseus.Amygdala.Nif),
      basal: nif_loaded?(Odysseus.Basal.Nif),
      cerebellum: nif_loaded?(Odysseus.Cerebellum.Nif),
      astrocyte: nif_loaded?(Odysseus.Astrocyte.Nif)
    }
  end

  defp nif_loaded?(module) do
    try do
      module.new_layer() || module.new_store() || module.new_state() || module.new_ganglia() || module.new_predictor() || module.new_cache(1)
      true
    rescue
      _ -> false
    end
  end

  defp structure_count, do: 16
end
