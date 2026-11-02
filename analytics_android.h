#ifndef VELO_ANALYTICS_ANDROID_H
#define VELO_ANALYTICS_ANDROID_H

#if defined(__ANDROID__)
#include <jni.h>
#include <android/native_activity.h>
#include <android/log.h>
#include <string.h>

extern const void* sapp_android_get_native_activity(void);

static inline int velo_android_http_post(const char* url_str, const char* api_key_str, const char* body_str) {
	const ANativeActivity* act = (const ANativeActivity*)sapp_android_get_native_activity();
	if (!act || !act->vm) return 0;
	JavaVM* vm = act->vm;
	JNIEnv* env = NULL;
	int detach = 0;
	if ((*vm)->GetEnv(vm, (void**)&env, JNI_VERSION_1_6) != JNI_OK) {
		if ((*vm)->AttachCurrentThread(vm, &env, NULL) != JNI_OK) return 0;
		detach = 1;
	}

	jclass url_cls = (*env)->FindClass(env, "java/net/URL");
	if (!url_cls) {
		if ((*env)->ExceptionCheck(env)) {
			(*env)->ExceptionDescribe(env);
			(*env)->ExceptionClear(env);
		}
		if (detach) (*vm)->DetachCurrentThread(vm);
		return 0;
	}
	jmethodID url_init = (*env)->GetMethodID(env, url_cls, "<init>", "(Ljava/lang/String;)V");
	jmethodID open_conn = (*env)->GetMethodID(env, url_cls, "openConnection", "()Ljava/net/URLConnection;");

	jstring jurl = (*env)->NewStringUTF(env, url_str);
	jobject url_obj = (*env)->NewObject(env, url_cls, url_init, jurl);
	(*env)->DeleteLocalRef(env, jurl);
	(*env)->DeleteLocalRef(env, url_cls);

	if (!url_obj || (*env)->ExceptionCheck(env)) {
		if ((*env)->ExceptionCheck(env)) {
			(*env)->ExceptionDescribe(env);
			(*env)->ExceptionClear(env);
		}
		if (detach) (*vm)->DetachCurrentThread(vm);
		return 0;
	}

	jobject conn = (*env)->CallObjectMethod(env, url_obj, open_conn);
	(*env)->DeleteLocalRef(env, url_obj);

	if (!conn || (*env)->ExceptionCheck(env)) {
		if ((*env)->ExceptionCheck(env)) {
			(*env)->ExceptionDescribe(env);
			(*env)->ExceptionClear(env);
		}
		if (detach) (*vm)->DetachCurrentThread(vm);
		return 0;
	}

	jclass http_cls = (*env)->FindClass(env, "java/net/HttpURLConnection");
	if (!http_cls) {
		if ((*env)->ExceptionCheck(env)) {
			(*env)->ExceptionDescribe(env);
			(*env)->ExceptionClear(env);
		}
		(*env)->DeleteLocalRef(env, conn);
		if (detach) (*vm)->DetachCurrentThread(vm);
		return 0;
	}
	jmethodID set_method = (*env)->GetMethodID(env, http_cls, "setRequestMethod", "(Ljava/lang/String;)V");
	jmethodID set_prop = (*env)->GetMethodID(env, http_cls, "setRequestProperty", "(Ljava/lang/String;Ljava/lang/String;)V");
	jmethodID set_do_out = (*env)->GetMethodID(env, http_cls, "setDoOutput", "(Z)V");
	jmethodID set_timeout = (*env)->GetMethodID(env, http_cls, "setConnectTimeout", "(I)V");
	jmethodID set_read_timeout = (*env)->GetMethodID(env, http_cls, "setReadTimeout", "(I)V");
	jmethodID get_out = (*env)->GetMethodID(env, http_cls, "getOutputStream", "()Ljava/io/OutputStream;");
	jmethodID get_resp = (*env)->GetMethodID(env, http_cls, "getResponseCode", "()I");
	jmethodID disconnect = (*env)->GetMethodID(env, http_cls, "disconnect", "()V");

	jstring jmethod = (*env)->NewStringUTF(env, "POST");
	(*env)->CallVoidMethod(env, conn, set_method, jmethod);
	(*env)->DeleteLocalRef(env, jmethod);

	(*env)->CallVoidMethod(env, conn, set_timeout, (jint)10000);
	(*env)->CallVoidMethod(env, conn, set_read_timeout, (jint)10000);
	(*env)->CallVoidMethod(env, conn, set_do_out, JNI_TRUE);

	jstring jct = (*env)->NewStringUTF(env, "Content-Type");
	jstring jct_val = (*env)->NewStringUTF(env, "application/json");
	(*env)->CallVoidMethod(env, conn, set_prop, jct, jct_val);
	(*env)->DeleteLocalRef(env, jct);
	(*env)->DeleteLocalRef(env, jct_val);

	jstring jkey = (*env)->NewStringUTF(env, "X-API-Key");
	jstring jkey_val = (*env)->NewStringUTF(env, api_key_str);
	(*env)->CallVoidMethod(env, conn, set_prop, jkey, jkey_val);
	(*env)->DeleteLocalRef(env, jkey);
	(*env)->DeleteLocalRef(env, jkey_val);

	jobject out_stream = (*env)->CallObjectMethod(env, conn, get_out);
	if (!out_stream || (*env)->ExceptionCheck(env)) {
		if ((*env)->ExceptionCheck(env)) {
			(*env)->ExceptionDescribe(env);
			(*env)->ExceptionClear(env);
		}
		(*env)->CallVoidMethod(env, conn, disconnect);
		(*env)->DeleteLocalRef(env, conn);
		(*env)->DeleteLocalRef(env, http_cls);
		if (detach) (*vm)->DetachCurrentThread(vm);
		return 0;
	}

	jclass out_cls = (*env)->FindClass(env, "java/io/OutputStream");
	jmethodID write_bytes = (*env)->GetMethodID(env, out_cls, "write", "([B)V");
	jmethodID close_stream = (*env)->GetMethodID(env, out_cls, "close", "()V");

	int body_len = (int)strlen(body_str);
	jbyteArray jbytes = (*env)->NewByteArray(env, body_len);
	(*env)->SetByteArrayRegion(env, jbytes, 0, body_len, (const jbyte*)body_str);
	(*env)->CallVoidMethod(env, out_stream, write_bytes, jbytes);
	(*env)->DeleteLocalRef(env, jbytes);
	(*env)->CallVoidMethod(env, out_stream, close_stream);
	(*env)->DeleteLocalRef(env, out_stream);
	(*env)->DeleteLocalRef(env, out_cls);

	int status = 0;
	if (!(*env)->ExceptionCheck(env)) {
		status = (*env)->CallIntMethod(env, conn, get_resp);
	} else {
		(*env)->ExceptionDescribe(env);
		(*env)->ExceptionClear(env);
	}
	__android_log_print(ANDROID_LOG_INFO, "AnalyticsJNI", "HTTP status: %d", status);
	(*env)->CallVoidMethod(env, conn, disconnect);
	(*env)->DeleteLocalRef(env, conn);
	(*env)->DeleteLocalRef(env, http_cls);

	if (detach) (*vm)->DetachCurrentThread(vm);
	return (status == 200 || status == 201 || status == 204) ? 1 : 0;
}
#endif

#endif // VELO_ANALYTICS_ANDROID_H
