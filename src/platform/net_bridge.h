#ifndef NET_BRIDGE_H
#define NET_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handle for a network fetch operation
typedef void *FetchHandle;

// Fetch status values mirroring Zig enum
typedef enum {
  FETCH_STATUS_PENDING = 0,
  FETCH_STATUS_SUCCESS = 1,
  FETCH_STATUS_ERROR = 2,
  FETCH_STATUS_TIMEOUT = 3,
} FetchStatus;

// Start an async HTTP/HTTPS request.
// Returns a FetchHandle that must be polled, then eventually freed.
// headers is a flat array of alternating names and values: [n1, v1, n2, v2...]
FetchHandle net_fetch_start(const char *url, const char *method,
                            const char **headers, int header_count,
                            const uint8_t *body, int body_len);

// Poll the status of the fetch operation.
FetchStatus net_fetch_poll(FetchHandle handle);

// Get the HTTP status code (e.g., 200). Only valid if status == SUCCESS.
int net_fetch_get_status_code(FetchHandle handle);

// Get the response body. Only valid if status == SUCCESS.
// Returns a pointer to the buffer and sets *out_len to its size.
// The buffer is owned by the FetchHandle and freed when net_fetch_free is
// called.
const uint8_t *net_fetch_get_body(FetchHandle handle, int *out_len);

// Get a specific response header value by name (case-insensitive).
// Copies the value into out_value, up to max_len bytes.
// Returns the length of the value, or 0 if not found.
int net_fetch_get_header(FetchHandle handle, const char *name, char *out_value,
                         int max_len);

// Get the number of response headers.
int net_fetch_get_header_count(FetchHandle handle);

// Get a response header by index. Copies name and value into the provided
// buffers. Returns 1 on success, 0 if index is out of range.
int net_fetch_get_header_at(FetchHandle handle, int index, char *out_name,
                            int name_max, char *out_value, int value_max);

// Free the fetch operation and all associated memory (including response body).
void net_fetch_free(FetchHandle handle);

#ifdef __cplusplus
}
#endif

#endif // NET_BRIDGE_H
