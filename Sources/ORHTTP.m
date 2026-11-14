#import "ORHTTP.h"


static NSString *ORHTTPMessageForStatus(NSInteger statusCode) {
    if (statusCode == 401) {
        return @"Требуется вход в каталог (HTTP 401). Укажите логин и пароль в настройках каталога.";
    }
    if (statusCode == 403) {
        return @"Доступ запрещён (HTTP 403). Возможно, нужен вход в каталог.";
    }
    if (statusCode == 404) {
        return @"Файл или страница не найдены (HTTP 404).";
    }
    return [NSString stringWithFormat:@"HTTP %ld", (long)statusCode];
}

@implementation ORHTTP

+ (NSURLSession *)session {
    static NSURLSession *session = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 60;
        config.timeoutIntervalForResource = 300;
        // Use a browser-like User-Agent to avoid blocking by sites like coollib.in
        // Include Accept and Accept-Language in additional headers so they're sent on redirect
        config.HTTPAdditionalHeaders = @{
            @"User-Agent": @"Mozilla/5.0 (iPhone; CPU iPhone OS 12_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.1 Mobile/15E148 Safari/604.1",
            @"Accept": @"application/atom+xml,application/xml,text/html,*/*",
            @"Accept-Language": @"ru,en;q=0.9"
        };
        session = [NSURLSession sessionWithConfiguration:config];
    });
    return session;
}

+ (void)GET:(NSString *)urlString
    headers:(NSDictionary<NSString *, NSString *> *)headers
 completion:(void (^)(NSData *, NSHTTPURLResponse *, NSError *))completion {
    [self request:urlString method:@"GET" body:nil headers:headers completion:completion];
}

+ (void)POST:(NSString *)urlString
        body:(NSData *)body
     headers:(NSDictionary<NSString *, NSString *> *)headers
  completion:(void (^)(NSData *, NSHTTPURLResponse *, NSError *))completion {
    [self request:urlString method:@"POST" body:body headers:headers completion:completion];
}

+ (void)request:(NSString *)urlString
         method:(NSString *)method
           body:(NSData *)body
        headers:(NSDictionary<NSString *, NSString *> *)headers
     completion:(void (^)(NSData *, NSHTTPURLResponse *, NSError *))completion {
    if (!completion) return;
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        completion(nil, nil, [NSError errorWithDomain:@"OmniReader.HTTP" code:1
                                              userInfo:@{NSLocalizedDescriptionKey: @"Некорректный URL"}]);
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;
    if (body) request.HTTPBody = body;
    for (NSString *key in headers) {
        [request setValue:headers[key] forHTTPHeaderField:key];
    }
    NSURLSessionDataTask *task = [[self session] dataTaskWithRequest:request
                                                   completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
        if (error) {
            completion(data, http, error);
            return;
        }
        if (http && (http.statusCode < 200 || http.statusCode >= 300)) {
            NSString *statusMessage = ORHTTPMessageForStatus(http.statusCode);
            NSError *httpError = [NSError errorWithDomain:@"OmniReader.HTTP"
                                                     code:http.statusCode
                                                 userInfo:@{NSLocalizedDescriptionKey: statusMessage}];
            completion(data, http, httpError);
            return;
        }
        completion(data, http, nil);
    }];
    [task resume];
}

+ (void)download:(NSString *)urlString
         headers:(NSDictionary<NSString *, NSString *> *)headers
          toPath:(NSString *)path
      completion:(void (^)(NSString *, NSError *))completion {
    if (!completion) return;
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url || path.length == 0) {
        completion(nil, [NSError errorWithDomain:@"OmniReader.HTTP" code:1
                                        userInfo:@{NSLocalizedDescriptionKey: @"Некорректный запрос"}]);
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    for (NSString *key in headers) {
        [request setValue:headers[key] forHTTPHeaderField:key];
    }
    NSURLSessionDownloadTask *task = [[self session] downloadTaskWithRequest:request
                                                           completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
        if (http && (http.statusCode < 200 || http.statusCode >= 300)) {
            NSString *statusMessage = ORHTTPMessageForStatus(http.statusCode);
            NSError *httpError = [NSError errorWithDomain:@"OmniReader.HTTP"
                                                     code:http.statusCode
                                                 userInfo:@{NSLocalizedDescriptionKey: statusMessage}];
            completion(nil, httpError);
            return;
        }
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm removeItemAtPath:path error:NULL];
        NSString *parent = [path stringByDeletingLastPathComponent];
        [fm createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:NULL];
        NSError *moveError = nil;
        BOOL moved = [fm moveItemAtURL:location toURL:[NSURL fileURLWithPath:path] error:&moveError];
        if (!moved) {
            completion(nil, moveError);
            return;
        }
        completion(path, nil);
    }];
    [task resume];
}

+ (NSString *)basicAuthorizationForUser:(NSString *)user password:(NSString *)password {
    NSString *pair = [NSString stringWithFormat:@"%@:%@", user ?: @"", password ?: @""];
    NSData *data = [pair dataUsingEncoding:NSUTF8StringEncoding];
    return [NSString stringWithFormat:@"Basic %@", [data base64EncodedStringWithOptions:0]];
}

@end
