defmodule PodlyWeb.RoomLive do
  use PodlyWeb, :live_view

  @impl true
  def mount(_, _, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Podly.PubSub, "streams")
      user_id = 2 |> :crypto.strong_rand_bytes() |> Base.encode16()
      channels = senders(user_id)

      {:ok, socket |> assign(:user_id, user_id) |> assign(:channels, channels)}
    else
      {:ok, socket |> assign(:user_id, nil) |> assign(:channels, [])}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div :if={@user_id} class="p-10">
      <div class="flex h-full wrap w-full gap-2">
        <div class="h-full grow-0 self-center">
          <video
            class="w-[20rem] h-max-[20rem] rounded-xl"
            phx-hook="WebRtcVideo"
            id="broadcaster"
            controlslist="nofullscreen nodownload noremoteplayback"
            autoplay
            user-id={@user_id}
            type="send"
            muted
          />
          <div class="absolute z-100 w-[20rem] text-center bg-[#2B825B] text-white rounded-xl mt-1">
            <%= @user_id %>
          </div>
        </div>
        <div class="grow flex flex-wrap w-[80vw] gap-2">
          <div :for={target_id <- @channels}>
            <video
              class="w-[40rem] h-[40rem] rounded-xl"
              phx-hook="WebRtcVideo"
              id={"channel_#{target_id}"}
              controlslist="nofullscreen nodownload noremoteplayback"
              target-id={target_id}
              autoplay
              user-id={@user_id}
              type="receive"
            />
            <div class="relative z-100 w-max-[40rem] text-center bg-[#2B825B] text-white rounded-xl mt-1">
              <%= target_id %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_info({:joined, _, _}, socket),
    do: {:noreply, assign(socket, :channels, senders(socket))}

  def handle_info({:left, _}, socket),
    do: {:noreply, assign(socket, :channels, senders(socket))}

  defp senders(%{assigns: %{user_id: self_user_id}}), do: senders(self_user_id)

  defp senders(self_user_id),
    do: self_user_id |> Podly.Room.get_senders() |> Enum.map(&elem(&1, 0))
end
