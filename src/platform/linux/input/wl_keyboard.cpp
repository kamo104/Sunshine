#ifdef SUNSHINE_BUILD_WAYLAND

#include <cerrno>
#include <cstdint>
#include <cstring>
#include <ctime>
#include <fcntl.h>
#include <ios>
#include <linux/input-event-codes.h>
#include <sys/syscall.h>
#include <unistd.h>

#ifndef MFD_CLOEXEC
#define MFD_CLOEXEC 0x0001U
#endif
#ifndef MFD_ALLOW_SEALING
#define MFD_ALLOW_SEALING 0x0002U
#endif
#ifndef F_ADD_SEALS
#define F_ADD_SEALS 1033
#endif
#ifndef F_SEAL_SHRINK
#define F_SEAL_SHRINK 0x0002
#endif
#ifndef F_SEAL_GROW
#define F_SEAL_GROW 0x0004
#endif
#ifndef F_SEAL_WRITE
#define F_SEAL_WRITE 0x0008
#endif
#ifndef F_SEAL_SEAL
#define F_SEAL_SEAL 0x0010
#endif

#include <map>
#include <string>

#include <wayland-client.h>

#include <virtual-keyboard-unstable-v1.h>

#include "src/config.h"
#include "src/logging.h"
#include "src/platform/common.h"
#include "src/utility.h"
#include "wl_keyboard.h"

namespace platf::wl_keyboard {

  namespace {

    uint32_t
    now_ms() {
      struct timespec ts;
      clock_gettime(CLOCK_MONOTONIC, &ts);
      return (uint32_t) (ts.tv_sec * 1000 + ts.tv_nsec / 1'000'000);
    }

    void
    registry_global(void *data, wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
      auto *state = reinterpret_cast<state_t *>(data);
      if (strcmp(interface, zwp_virtual_keyboard_manager_v1_interface.name) == 0) {
        state->manager = reinterpret_cast<zwp_virtual_keyboard_manager_v1 *>(
          wl_registry_bind(registry, name, &zwp_virtual_keyboard_manager_v1_interface, version));
      }
      else if (strcmp(interface, "wl_seat") == 0) {
        state->seat = reinterpret_cast<wl_seat *>(
          wl_registry_bind(registry, name, &wl_seat_interface, 1));
      }
    }

    void
    registry_global_remove(void *, wl_registry *, uint32_t) {
    }

    constexpr wl_registry_listener registry_listener = {
      .global = registry_global,
      .global_remove = registry_global_remove,
    };

    int
    memfd_create_sealed(const char *name) {
#ifdef __NR_memfd_create
      return (int) syscall(__NR_memfd_create, name, MFD_CLOEXEC | MFD_ALLOW_SEALING);
#else
      errno = ENOSYS;
      return -1;
#endif
    }

    bool
    set_keymap(zwp_virtual_keyboard_v1 *kb) {
      const char keymap_str[] =
        "xkb_keymap {\n"
        "\txkb_keycodes { include \"evdev+aliases(qwerty)\" };\n"
        "\txkb_types    { include \"complete\" };\n"
        "\txkb_compat   { include \"complete\" };\n"
        "\txkb_symbols  { include \"pc+us+inet(evdev)\" };\n"
        "};\n";

      size_t size = sizeof(keymap_str) - 1;

      int fd = memfd_create_sealed("xkb-keymap");
      if (fd < 0) {
        BOOST_LOG(error) << "wl_keyboard: memfd_create failed: " << strerror(errno);
        return false;
      }

      ssize_t written = write(fd, keymap_str, size);
      if (written < 0 || (size_t) written != size) {
        BOOST_LOG(error) << "wl_keyboard: failed to write keymap: " << strerror(errno);
        close(fd);
        return false;
      }

      lseek(fd, 0, SEEK_SET);

      fcntl(fd, F_ADD_SEALS, F_SEAL_SHRINK | F_SEAL_GROW | F_SEAL_WRITE | F_SEAL_SEAL);

      zwp_virtual_keyboard_v1_keymap(kb, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, (uint32_t) size);
      close(fd);

      return true;
    }

  }  // anonymous namespace

  bool
  state_t::init() {
    display = wl_display_connect(nullptr);
    if (!display) {
      BOOST_LOG(error) << "wl_keyboard: failed to connect to Wayland display";
      return false;
    }

    registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, this);
    wl_display_roundtrip(display);

    if (!manager) {
      BOOST_LOG(error) << "wl_keyboard: compositor does not support zwp_virtual_keyboard_manager_v1";
      destroy();
      return false;
    }

    if (!seat) {
      BOOST_LOG(error) << "wl_keyboard: no wl_seat found";
      destroy();
      return false;
    }

    keyboard = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(manager, seat);
    wl_display_roundtrip(display);

    if (!set_keymap(keyboard)) {
      BOOST_LOG(error) << "wl_keyboard: failed to set keymap";
      destroy();
      return false;
    }

    wl_display_roundtrip(display);

    BOOST_LOG(info) << "wl_keyboard: virtual keyboard initialized";
    return true;
  }

  void
  state_t::destroy() {
    if (keyboard) {
      zwp_virtual_keyboard_v1_destroy(keyboard);
      keyboard = nullptr;
    }
    if (seat) {
      wl_seat_destroy(seat);
      seat = nullptr;
    }
    if (registry) {
      wl_registry_destroy(registry);
      registry = nullptr;
    }
    if (display) {
      wl_display_disconnect(display);
      display = nullptr;
    }
  }

  // Build reverse mapping from Windows VK code -> Linux evdev code.
  // The forward mapping (key_mappings in inputtino_keyboard.cpp) maps
  // KEY_* -> VK_*, so we reverse it here and fill in any gaps.
  static const std::map<uint16_t, uint16_t> vk_to_evdev = {
    {0x08, KEY_BACKSPACE},
    {0x09, KEY_TAB},
    {0x0D, KEY_ENTER},
    {0x10, KEY_LEFTSHIFT},
    {0x11, KEY_LEFTCTRL},
    {0x12, KEY_LEFTALT},
    {0x14, KEY_CAPSLOCK},
    {0x1B, KEY_ESC},
    {0x20, KEY_SPACE},
    {0x21, KEY_PAGEUP},
    {0x22, KEY_PAGEDOWN},
    {0x23, KEY_END},
    {0x24, KEY_HOME},
    {0x25, KEY_LEFT},
    {0x26, KEY_UP},
    {0x27, KEY_RIGHT},
    {0x28, KEY_DOWN},
    {0x2C, KEY_SYSRQ},
    {0x2D, KEY_INSERT},
    {0x2E, KEY_DELETE},
    {0x30, KEY_0},
    {0x31, KEY_1},
    {0x32, KEY_2},
    {0x33, KEY_3},
    {0x34, KEY_4},
    {0x35, KEY_5},
    {0x36, KEY_6},
    {0x37, KEY_7},
    {0x38, KEY_8},
    {0x39, KEY_9},
    {0x41, KEY_A},
    {0x42, KEY_B},
    {0x43, KEY_C},
    {0x44, KEY_D},
    {0x45, KEY_E},
    {0x46, KEY_F},
    {0x47, KEY_G},
    {0x48, KEY_H},
    {0x49, KEY_I},
    {0x4A, KEY_J},
    {0x4B, KEY_K},
    {0x4C, KEY_L},
    {0x4D, KEY_M},
    {0x4E, KEY_N},
    {0x4F, KEY_O},
    {0x50, KEY_P},
    {0x51, KEY_Q},
    {0x52, KEY_R},
    {0x53, KEY_S},
    {0x54, KEY_T},
    {0x55, KEY_U},
    {0x56, KEY_V},
    {0x57, KEY_W},
    {0x58, KEY_X},
    {0x59, KEY_Y},
    {0x5A, KEY_Z},
    {0x5B, KEY_LEFTMETA},
    {0x5C, KEY_RIGHTMETA},
    {0x60, KEY_KP0},
    {0x61, KEY_KP1},
    {0x62, KEY_KP2},
    {0x63, KEY_KP3},
    {0x64, KEY_KP4},
    {0x65, KEY_KP5},
    {0x66, KEY_KP6},
    {0x67, KEY_KP7},
    {0x68, KEY_KP8},
    {0x69, KEY_KP9},
    {0x6A, KEY_KPASTERISK},
    {0x6B, KEY_KPPLUS},
    {0x6D, KEY_KPMINUS},
    {0x6E, KEY_KPDOT},
    {0x6F, KEY_KPSLASH},
    {0x70, KEY_F1},
    {0x71, KEY_F2},
    {0x72, KEY_F3},
    {0x73, KEY_F4},
    {0x74, KEY_F5},
    {0x75, KEY_F6},
    {0x76, KEY_F7},
    {0x77, KEY_F8},
    {0x78, KEY_F9},
    {0x79, KEY_F10},
    {0x7A, KEY_F11},
    {0x7B, KEY_F12},
    {0x7C, KEY_F13},
    {0x7D, KEY_F14},
    {0x7E, KEY_F15},
    {0x7F, KEY_F16},
    {0x80, KEY_F17},
    {0x81, KEY_F18},
    {0x82, KEY_F19},
    {0x83, KEY_F20},
    {0x84, KEY_F21},
    {0x85, KEY_F22},
    {0x86, KEY_F23},
    {0x87, KEY_F24},
    {0x90, KEY_NUMLOCK},
    {0x91, KEY_SCROLLLOCK},
    {0xA0, KEY_LEFTSHIFT},
    {0xA1, KEY_RIGHTSHIFT},
    {0xA2, KEY_LEFTCTRL},
    {0xA3, KEY_RIGHTCTRL},
    {0xA4, KEY_LEFTALT},
    {0xA5, KEY_RIGHTALT},
    {0xBA, KEY_SEMICOLON},
    {0xBB, KEY_EQUAL},
    {0xBC, KEY_COMMA},
    {0xBD, KEY_MINUS},
    {0xBE, KEY_DOT},
    {0xBF, KEY_SLASH},
    {0xC0, KEY_GRAVE},
    {0xDB, KEY_LEFTBRACE},
    {0xDC, KEY_BACKSLASH},
    {0xDD, KEY_RIGHTBRACE},
    {0xDE, KEY_APOSTROPHE},
    {0xE2, KEY_102ND},
  };

  void
  update(state_t *state, uint16_t modcode, bool release) {
    auto it = vk_to_evdev.find(modcode);
    if (it == vk_to_evdev.end()) {
      BOOST_LOG(warning) << "wl_keyboard: unknown VK code: 0x" << std::hex << modcode;
      return;
    }

    uint32_t state_val = release ? WL_KEYBOARD_KEY_STATE_RELEASED : WL_KEYBOARD_KEY_STATE_PRESSED;
    zwp_virtual_keyboard_v1_key(state->keyboard, now_ms(), it->second, state_val);
    wl_display_flush(state->display);
  }

}  // namespace platf::wl_keyboard

#endif  // SUNSHINE_BUILD_WAYLAND
