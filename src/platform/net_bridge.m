#import "net_bridge.h"
#import <Foundation/Foundation.h>

@interface FetchOperation : NSObject
@property(atomic, assign) FetchStatus status;
@property(atomic, assign) NSInteger statusCode;
@property(atomic, strong) NSData *responseData;
@property(atomic, strong) NSDictionary *responseHeaders;
@property(atomic, strong) NSString *finalURL;
@property(atomic, strong) NSURLSessionDataTask *task;
@end

@implementation FetchOperation
@end

FetchHandle net_fetch_start(const char *url_cstr, const char *method_cstr,
                            const char **headers, int header_count,
                            const uint8_t *body, int body_len) {
  if (!url_cstr || !method_cstr)
    return NULL;

  NSString *urlString = [NSString stringWithUTF8String:url_cstr];
  NSURL *url = [NSURL URLWithString:urlString];
  if (!url)
    return NULL;

  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  [request setHTTPMethod:[NSString stringWithUTF8String:method_cstr]];

  // Default headers
  [request setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15 MetalBrowser/0.1" forHTTPHeaderField:@"User-Agent"];
  [request setValue:@"gzip, deflate" forHTTPHeaderField:@"Accept-Encoding"];
  [request setValue:@"text/html,application/xhtml+xml,*/*"
      forHTTPHeaderField:@"Accept"];

  // User-provided headers (override defaults if present)
  for (int i = 0; i < header_count * 2; i += 2) {
    if (headers[i] && headers[i + 1]) {
      NSString *key = [NSString stringWithUTF8String:headers[i]];
      NSString *val = [NSString stringWithUTF8String:headers[i + 1]];
      [request setValue:val forHTTPHeaderField:key];
    }
  }

  if (body && body_len > 0) {
    [request setHTTPBody:[NSData dataWithBytes:body length:body_len]];
  }

  FetchOperation *op = [[FetchOperation alloc] init];
  op.status = FETCH_STATUS_PENDING;
  op.statusCode = 0;
  op.responseHeaders = nil;
  op.finalURL = urlString;

  NSURLSession *session = [NSURLSession sharedSession];
  NSURLSessionDataTask *task = [session
      dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response,
                            NSError *error) {
          if (error) {
            if ([error.domain isEqualToString:NSURLErrorDomain] &&
                error.code == NSURLErrorTimedOut) {
              op.status = FETCH_STATUS_TIMEOUT;
            } else {
              op.status = FETCH_STATUS_ERROR;
            }
          } else {
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
              NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
              op.statusCode = httpResponse.statusCode;
              op.responseHeaders = httpResponse.allHeaderFields;
              if (httpResponse.URL.absoluteString) {
                op.finalURL = httpResponse.URL.absoluteString;
              }
            } else {
              op.statusCode = 200;
              op.responseHeaders = @{};
              if (response.URL.absoluteString) {
                op.finalURL = response.URL.absoluteString;
              }
            }
            op.responseData = data;
            op.status = FETCH_STATUS_SUCCESS;
          }
        }];

  op.task = task;
  [task resume];

  return (__bridge_retained void *)op;
}

FetchStatus net_fetch_poll(FetchHandle handle) {
  if (!handle)
    return FETCH_STATUS_ERROR;
  FetchOperation *op = (__bridge FetchOperation *)handle;
  return op.status;
}

int net_fetch_get_status_code(FetchHandle handle) {
  if (!handle)
    return 0;
  FetchOperation *op = (__bridge FetchOperation *)handle;
  return (int)op.statusCode;
}

const uint8_t *net_fetch_get_body(FetchHandle handle, int *out_len) {
  if (!handle || !out_len)
    return NULL;
  FetchOperation *op = (__bridge FetchOperation *)handle;

  NSData *data = op.responseData;
  if (data) {
    *out_len = (int)[data length];
    return [data bytes];
  }

  *out_len = 0;
  return NULL;
}

int net_fetch_get_header(FetchHandle handle, const char *name, char *out_value,
                         int max_len) {
  if (!handle || !name || !out_value || max_len <= 0)
    return 0;
  FetchOperation *op = (__bridge FetchOperation *)handle;

  NSDictionary *hdrs = op.responseHeaders;
  if (!hdrs)
    return 0;

  NSString *key = [NSString stringWithUTF8String:name];
  // NSHTTPURLResponse headers are case-insensitive via NSDictionary lookup
  NSString *val = hdrs[key];
  if (!val) {
    // Manual case-insensitive search
    for (NSString *k in hdrs) {
      if ([k caseInsensitiveCompare:key] == NSOrderedSame) {
        val = hdrs[k];
        break;
      }
    }
  }
  if (!val)
    return 0;

  const char *utf8 = [val UTF8String];
  int len = (int)strlen(utf8);
  int copy_len = (len < max_len - 1) ? len : (max_len - 1);
  memcpy(out_value, utf8, copy_len);
  out_value[copy_len] = '\0';
  return len;
}

int net_fetch_get_header_count(FetchHandle handle) {
  if (!handle)
    return 0;
  FetchOperation *op = (__bridge FetchOperation *)handle;
  NSDictionary *hdrs = op.responseHeaders;
  return hdrs ? (int)[hdrs count] : 0;
}

int net_fetch_get_header_at(FetchHandle handle, int index, char *out_name,
                            int name_max, char *out_value, int value_max) {
  if (!handle || !out_name || !out_value || name_max <= 0 || value_max <= 0)
    return 0;
  FetchOperation *op = (__bridge FetchOperation *)handle;

  NSDictionary *hdrs = op.responseHeaders;
  if (!hdrs || index < 0 || index >= (int)[hdrs count])
    return 0;

  NSArray *keys = [hdrs allKeys];
  NSString *key = keys[index];
  NSString *val = hdrs[key];

  const char *key_utf8 = [key UTF8String];
  int klen = (int)strlen(key_utf8);
  int kcopy = (klen < name_max - 1) ? klen : (name_max - 1);
  memcpy(out_name, key_utf8, kcopy);
  out_name[kcopy] = '\0';

  const char *val_utf8 = [val UTF8String];
  int vlen = (int)strlen(val_utf8);
  int vcopy = (vlen < value_max - 1) ? vlen : (value_max - 1);
  memcpy(out_value, val_utf8, vcopy);
  out_value[vcopy] = '\0';

  return 1;
}

int net_fetch_get_final_url(FetchHandle handle, char *out_url, int max_len) {
  if (!handle || !out_url || max_len <= 0)
    return 0;
  FetchOperation *op = (__bridge FetchOperation *)handle;
  NSString *url = op.finalURL;
  if (!url)
    return 0;
  const char *utf8 = [url UTF8String];
  if (!utf8)
    return 0;
  int len = (int)strlen(utf8);
  int copy_len = (len < max_len - 1) ? len : (max_len - 1);
  memcpy(out_url, utf8, copy_len);
  out_url[copy_len] = '\0';
  return copy_len;
}

void net_fetch_free(FetchHandle handle) {
  if (!handle)
    return;
  FetchOperation *op = (__bridge_transfer FetchOperation *)handle;

  if (op.status == FETCH_STATUS_PENDING && op.task) {
    [op.task cancel];
  }
  // Memory is freed by ARC as op goes out of scope here
}
