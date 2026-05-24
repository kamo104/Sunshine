#pragma once

#ifdef SUNSHINE_BUILD_WAYLAND

#include <vector>

#include <wayland-client.h>

struct zwp_virtual_keyboard_manager_v1;
struct zwp_virtual_keyboard_v1;

namespace platf::wl_keyboard {

  struct state_t {
    wl_display *display = nullptr;
    wl_registry *registry = nullptr;
    zwp_virtual_keyboard_manager_v1 *manager = nullptr;
    zwp_virtual_keyboard_v1 *keyboard = nullptr;
    wl_seat *seat = nullptr;

    bool init();
    void destroy();
  };

  void update(state_t *state, uint16_t modcode, bool release);

}  // namespace platf::wl_keyboard

#endif  // SUNSHINE_BUILD_WAYLAND
