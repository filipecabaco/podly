defmodule PodlyWeb.RoomLive do
  use PodlyWeb, :live_view

  @impl true
  def mount(_, _session, socket) do
    Phoenix.PubSub.subscribe(Podly.PubSub, "senders")
    user_id = 2 |> :crypto.strong_rand_bytes() |> Base.encode16()
    channels = senders(user_id)

    {:ok, socket |> assign(:user_id, user_id) |> assign(:channels, channels)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-10">
      <div class="flex h-full wrap w-full gap-2">
        <div class="h-full grow-0 self-center">
          <video
            class="w-[20rem] rounded-xl"
            phx-hook="WebRtcVideo"
            id="broadcaster"
            controlslist="nofullscreen nodownload noremoteplayback"
            autoplay
            user-id={@user_id}
            type="send"
            muted
          />
          <div class="absolute z-100 w-[20rem] text-center bg-[#2B825B] text-white rounded-xl mt-2">
            <%= @user_id %>
          </div>
        </div>
        <div class="grow flex flex-wrap w-[80vw] gap-2">
          <div :for={{target_id, _} <- @channels}>
            <video
              class="w-[40rem] rounded-xl"
              phx-hook="WebRtcVideo"
              id={"channel_#{target_id}"}
              controlslist="nofullscreen nodownload noremoteplayback"
              target-id={target_id}
              autoplay
              user-id={@user_id}
              type="receive"
            />
            <div class="relative z-100 w-[40rem] text-center bg-[#2B825B] text-white rounded-xl mt-2">
              <%= target_id %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true

  def handle_info(:added, socket), do: {:noreply, assign(socket, :channels, senders(socket))}
  def handle_info(:removed, socket), do: {:noreply, assign(socket, :channels, senders(socket))}

  defp senders(%{assigns: %{user_id: self_user_id}}), do: senders(self_user_id)

  defp senders(self_user_id) do
    :podly_senders
    |> :ets.tab2list()
    |> Enum.uniq()
    |> Enum.reject(fn {id, _} -> id == self_user_id end)
  end
end
