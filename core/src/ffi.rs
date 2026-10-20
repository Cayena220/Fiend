use std::ffi::{c_char, CStr, CString};

/// C entry point used by the Flutter app. Takes a UTF-8 JSON request and returns a
/// heap-allocated UTF-8 JSON response that must be released with [`fiend_free`].
#[no_mangle]
pub extern "C" fn fiend_invoke(request: *const c_char) -> *mut c_char {
    let response = std::panic::catch_unwind(|| {
        if request.is_null() {
            return r#"{"ok":false,"error":"Empty request"}"#.to_string();
        }
        let text = unsafe { CStr::from_ptr(request) }.to_string_lossy();
        crate::invoke_json(&text)
    })
    .unwrap_or_else(|_| r#"{"ok":false,"error":"The Fiend engine hit an internal error"}"#.to_string());

    CString::new(response.replace('\0', ""))
        .unwrap_or_default()
        .into_raw()
}

/// Releases a string returned by [`fiend_invoke`].
///
/// # Safety
/// `ptr` must come from `fiend_invoke` and be freed exactly once.
#[no_mangle]
pub unsafe extern "C" fn fiend_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}
