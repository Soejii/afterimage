#include <Windows.h>
#include <ViGEm/Client.h>

#include <cstdint>
#include <new>

namespace {

constexpr std::uint32_t kAllocationFailed = 0xE1000001;
thread_local std::uint32_t last_error = VIGEM_ERROR_NONE;

struct ControllerHandle {
  PVIGEM_CLIENT client = nullptr;
  PVIGEM_TARGET target = nullptr;
};

void clean_up(ControllerHandle* handle, bool remove_target) {
  if (handle == nullptr) {
    return;
  }
  if (handle->target != nullptr) {
    if (remove_target && handle->client != nullptr) {
      vigem_target_remove(handle->client, handle->target);
    }
    vigem_target_free(handle->target);
  }
  if (handle->client != nullptr) {
    vigem_disconnect(handle->client);
    vigem_free(handle->client);
  }
  delete handle;
}

}  // namespace

extern "C" __declspec(dllexport) std::uint32_t afterimage_controller_probe() {
  auto* client = vigem_alloc();
  if (client == nullptr) {
    return kAllocationFailed;
  }
  const auto result = vigem_connect(client);
  if (result == VIGEM_ERROR_NONE) {
    vigem_disconnect(client);
  }
  vigem_free(client);
  return result;
}

extern "C" __declspec(dllexport) void* afterimage_controller_create() {
  last_error = VIGEM_ERROR_NONE;
  auto* handle = new (std::nothrow) ControllerHandle();
  if (handle == nullptr) {
    last_error = kAllocationFailed;
    return nullptr;
  }
  handle->client = vigem_alloc();
  if (handle->client == nullptr) {
    last_error = kAllocationFailed;
    clean_up(handle, false);
    return nullptr;
  }
  last_error = vigem_connect(handle->client);
  if (last_error != VIGEM_ERROR_NONE) {
    clean_up(handle, false);
    return nullptr;
  }
  handle->target = vigem_target_x360_alloc();
  if (handle->target == nullptr) {
    last_error = kAllocationFailed;
    clean_up(handle, false);
    return nullptr;
  }
  last_error = vigem_target_add(handle->client, handle->target);
  if (last_error != VIGEM_ERROR_NONE) {
    clean_up(handle, false);
    return nullptr;
  }
  return handle;
}

extern "C" __declspec(dllexport) std::uint32_t
afterimage_controller_last_error() {
  return last_error;
}

extern "C" __declspec(dllexport) std::uint32_t afterimage_controller_update(
    void* raw_handle,
    std::uint16_t buttons) {
  auto* handle = static_cast<ControllerHandle*>(raw_handle);
  if (handle == nullptr || handle->client == nullptr ||
      handle->target == nullptr) {
    return VIGEM_ERROR_INVALID_TARGET;
  }
  XUSB_REPORT report{};
  report.wButtons = buttons;
  return vigem_target_x360_update(handle->client, handle->target, report);
}

extern "C" __declspec(dllexport) std::uint32_t afterimage_controller_destroy(
    void* raw_handle) {
  auto* handle = static_cast<ControllerHandle*>(raw_handle);
  if (handle == nullptr) {
    return VIGEM_ERROR_INVALID_TARGET;
  }
  XUSB_REPORT report{};
  const auto neutral_result =
      vigem_target_x360_update(handle->client, handle->target, report);
  const auto remove_result = vigem_target_remove(handle->client, handle->target);
  clean_up(handle, false);
  return remove_result == VIGEM_ERROR_NONE ? neutral_result : remove_result;
}
