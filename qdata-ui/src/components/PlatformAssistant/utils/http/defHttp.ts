import axios, { type AxiosInstance, type AxiosRequestConfig, type AxiosResponse } from 'axios';
import { ElMessage } from 'element-plus';
import { getToken } from '../auth';

type ErrorMessageMode = 'none' | 'message';

interface RequestOptions {
  withToken?: boolean;
  isTransformResponse?: boolean;
  isReturnNativeResponse?: boolean;
  errorMessageMode?: ErrorMessageMode;
}

interface DefHttpRequestConfig extends AxiosRequestConfig {
  requestOptions?: RequestOptions;
}

interface BackendResult<T = any> {
  code?: number;
  msg?: string;
  message?: string;
  data?: T;
}

interface DefHttpError extends Error {
  __defHttpHandled?: boolean;
}

const DEFAULT_REQUEST_OPTIONS: Required<RequestOptions> = {
  withToken: true,
  isTransformResponse: true,
  isReturnNativeResponse: false,
  errorMessageMode: 'message',
};

function normalizeBaseUrl(): string {
  const globUrl = String(import.meta.env.VITE_GLOB_API_URL ?? '').trim();
  const globPrefix = String(import.meta.env.VITE_GLOB_API_URL_PREFIX ?? '').trim();
  const aiUrl = String(import.meta.env.VITE_APP_BASE_AI ?? '').trim();
  const apiUrl = String(import.meta.env.VITE_APP_BASE_API ?? '').trim();

  return globUrl || globPrefix ? `${globUrl}${globPrefix}` : aiUrl || apiUrl;
}

function isSuccessCode(code?: number): boolean {
  return code === undefined || code === 0 || code === 200;
}

function showError(message: string, mode: ErrorMessageMode): void {
  if (mode !== 'none' && message) {
    ElMessage.error(message);
  }
}

class SimpleDefHttp {
  private readonly axiosInstance: AxiosInstance;

  constructor() {
    this.axiosInstance = axios.create({
      baseURL: normalizeBaseUrl(),
      timeout: 600000,
    });
  }

  get<T = any>(config: DefHttpRequestConfig, options?: RequestOptions): Promise<T> {
    return this.request<T>({ ...config, method: 'GET' }, options);
  }

  post<T = any>(config: DefHttpRequestConfig, options?: RequestOptions): Promise<T> {
    return this.request<T>({ ...config, method: 'POST' }, options);
  }

  put<T = any>(config: DefHttpRequestConfig, options?: RequestOptions): Promise<T> {
    return this.request<T>({ ...config, method: 'PUT' }, options);
  }

  delete<T = any>(config: DefHttpRequestConfig, options?: RequestOptions): Promise<T> {
    return this.request<T>({ ...config, method: 'DELETE' }, options);
  }

  private async request<T = any>(config: DefHttpRequestConfig, options?: RequestOptions): Promise<T> {
    const requestOptions: Required<RequestOptions> = {
      ...DEFAULT_REQUEST_OPTIONS,
      ...options,
      ...config.requestOptions,
    };
    const requestConfig = this.prepareConfig(config, requestOptions);

    try {
      const response = await this.axiosInstance.request<BackendResult<T>, AxiosResponse<BackendResult<T>>>(
        requestConfig,
      );

      return this.transformResponse<T>(response, requestOptions);
    } catch (error: any) {
      const handledError = error as DefHttpError;

      if (!handledError.__defHttpHandled) {
        showError(this.getErrorMessage(error), requestOptions.errorMessageMode);
      }

      throw error;
    }
  }

  private prepareConfig(config: DefHttpRequestConfig, options: Required<RequestOptions>): AxiosRequestConfig {
    const headers: Record<string, any> = { ...(config.headers as Record<string, any>) };
    const token = getToken();

    if (options.withToken && token) {
      headers.Authorization = `Bearer ${token}`;
    }

    if (typeof FormData !== 'undefined' && config.data instanceof FormData) {
      delete headers['Content-Type'];
      delete headers['content-type'];
    } else if (config.data && !headers['Content-Type'] && !headers['content-type']) {
      headers['Content-Type'] = 'application/json;charset=UTF-8';
    }

    const { requestOptions: _requestOptions, ...axiosConfig } = config;

    return {
      ...axiosConfig,
      headers,
    };
  }

  private transformResponse<T>(
    response: AxiosResponse<BackendResult<T>>,
    options: Required<RequestOptions>,
  ): T {
    if (response.request?.responseType === 'blob' || response.request?.responseType === 'arraybuffer') {
      return response.data as T;
    }

    if (options.isReturnNativeResponse) {
      return response as T;
    }

    if (!options.isTransformResponse) {
      return response.data as T;
    }

    const result = response.data;

    if (!isSuccessCode(result?.code)) {
      const message = result?.msg || result?.message || '请求失败';
      showError(message, options.errorMessageMode);

      const error = new Error(message) as DefHttpError;
      error.__defHttpHandled = true;
      throw error;
    }

    // PlatformAssistant 的调用方需要完整 { code, msg, data } 信封，因此成功时不自动解包 data。
    return result as T;
  }

  private getErrorMessage(error: any): string {
    if (error?.response?.data?.msg) {
      return error.response.data.msg;
    }

    if (error?.response?.data?.message) {
      return error.response.data.message;
    }

    if (error?.message?.includes('timeout')) {
      return '请求超时，请稍后重试';
    }

    if (error?.message === 'Network Error') {
      return '网络连接异常，请检查服务是否可用';
    }

    return error?.message || '网络请求失败';
  }
}

export const defHttp = new SimpleDefHttp();
export type { DefHttpRequestConfig, RequestOptions };
