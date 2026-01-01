import { httpRequest } from "@/services/http-client"
import { tokenStorage } from "@/services/token-storage"
import type {
  Chat,
  CreateChatRequest,
  DeleteChatParams,
  LoginRequest,
  LoginResponse,
  Message,
  RegisterRequest,
  UpdateAvatarRequest,
  UpdateUsernameRequest,
  UserResponse,
} from "@/types/api"

export const chatKeys = {
  all: ["chats"] as const,
  list: () => [...chatKeys.all, "list"] as const,
  detail: (chatId: number) => [...chatKeys.all, chatId] as const,
  messages: (chatId: number) => [...chatKeys.detail(chatId), "messages"] as const,
}

export const authApi = {
  login: (body: LoginRequest) =>
    httpRequest<LoginResponse>("/auth/login", { method: "POST", body }).then((res) => {
      tokenStorage.set(res.token)
      return res
    }),
  register: (body: RegisterRequest) =>
    httpRequest<UserResponse>("/auth/register", { method: "POST", body }),
}

export const userApi = {
  me: () => httpRequest<UserResponse>("/users/me"),
  updateUsername: (body: UpdateUsernameRequest) =>
    httpRequest<UserResponse>("/users/username", { method: "PATCH", body }),
  updateAvatar: (body: UpdateAvatarRequest) =>
    httpRequest<UserResponse>("/users/avatar", { method: "PATCH", body }),
  deleteMe: () => httpRequest<void>("/users/me", { method: "DELETE" }),
}

export const chatApi = {
  create: (body: CreateChatRequest) => httpRequest<Chat>("/chats", { method: "POST", body }),
  list: () => httpRequest<Chat[]>("/chats"),
  messages: (chatId: number) => httpRequest<Message[]>(`/chats/${chatId}/messages`),
  delete: ({ id, for_all }: DeleteChatParams) => {
    const query = for_all ? `?for_all=${String(for_all)}` : ""
    return httpRequest<void>(`/chats/${id}${query}`, {
      method: "DELETE",
    })
  },
}

export const authQueryOptions = {
  me: () => ({
    queryKey: ["auth", "me"] as const,
    queryFn: userApi.me,
  }),
}

export const chatQueryOptions = {
  list: () => ({
    queryKey: chatKeys.list(),
    queryFn: chatApi.list,
  }),
  messages: (chatId: number) => ({
    queryKey: chatKeys.messages(chatId),
    queryFn: () => chatApi.messages(chatId),
  }),
}
