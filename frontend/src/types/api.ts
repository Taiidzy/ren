export type ChatKind = "private" | "group"

export interface UserResponse {
  id: number
  login: string
  username: string
  avatar: string | null
}

export interface Chat {
  id: number
  kind: ChatKind
  title: string | null
  created_at: string
  updated_at: string
  is_archived: boolean | null
  peer_avatar: string | null
  peer_username: string
}

export interface Message {
  id: number
  chat_id: number
  sender_id: number
  body: string | null
  created_at: string
}

export interface ApiErrorResponse {
  error: string
}

export interface LoginRequest {
  login: string
  password: string
  remember_me?: boolean
}

export interface LoginResponse {
  message: string
  user: UserResponse
  token: string
}

export interface RegisterRequest {
  login: string
  username: string
  avatar: string | null
  password: string
}

export interface UpdateUsernameRequest {
  username: string
}

export interface UpdateAvatarRequest {
  avatar: string | null
}

export interface CreateGroupChatRequest {
  kind: "group"
  title: string
  user_ids: number[]
}

export interface CreatePrivateChatRequest {
  kind: "private"
  user_ids: number[]
}

export type CreateChatRequest = CreateGroupChatRequest | CreatePrivateChatRequest

export interface DeleteChatParams {
  id: number
  for_all?: boolean
}
