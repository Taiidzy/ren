import { z } from "zod"

export const userResponseSchema = z.object({
  id: z.number(),
  login: z.string(),
  username: z.string(),
  avatar: z.string().url().nullable(),
})

export const chatSchema = z.object({
  id: z.number(),
  kind: z.union([z.literal("private"), z.literal("group")]),
  title: z.string().nullable(),
  created_at: z.string(),
  updated_at: z.string(),
  is_archived: z.boolean().nullable(),
  peer_avatar: z.string().nullable(),
  peer_username: z.string(),
})

export const messageSchema = z.object({
  id: z.number(),
  chat_id: z.number(),
  sender_id: z.number(),
  body: z.string().nullable(),
  created_at: z.string(),
})

export const loginResponseSchema = z.object({
  message: z.string(),
  user: userResponseSchema,
  token: z.string(),
})

export const apiErrorSchema = z.object({
  error: z.string(),
})
