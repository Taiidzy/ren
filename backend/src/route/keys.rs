use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
    Router,
};
use axum::routing::{get, post, delete};
use crate::{AppState, models::prekeys::*, middleware::CurrentUser};

/// GET /keys/{user_id}/bundle
/// Получить PreKey Bundle для X3DH инициализации
pub async fn get_prekey_bundle(
    State(state): State<AppState>,
    Path(user_id): Path<i32>,
) -> Result<Json<PreKeyBundleResponse>, StatusCode> {
    let pool = &state.pool;
    
    // 1. Получить Identity Key пользователя
    let identity_key = sqlx::query_scalar::<_, Option<String>>(
        "SELECT identity_public_key FROM users WHERE id = $1"
    )
    .bind(user_id)
    .fetch_one(pool)
    .await
    .map_err(|_| StatusCode::NOT_FOUND)?
    .ok_or(StatusCode::NOT_FOUND)?;
    
    // 2. Получить текущий Signed PreKey
    let signed_prekey = sqlx::query_as::<_, SignedPreKey>(
        "SELECT id, user_id, prekey_public, signature, created_at, is_current 
         FROM signed_prekeys 
         WHERE user_id = $1 AND is_current = TRUE 
         LIMIT 1"
    )
    .bind(user_id)
    .fetch_optional(pool)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
    .ok_or(StatusCode::NOT_FOUND)?;
    
    // 3. Получить один неиспользованный One-Time PreKey
    let otp = sqlx::query_as::<_, PreKey>(
        "SELECT id, user_id, prekey_id, prekey_public, created_at, used_at 
         FROM prekeys 
         WHERE user_id = $1 AND used_at IS NULL 
         LIMIT 1"
    )
    .bind(user_id)
    .fetch_optional(pool)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    // 4. Собрать bundle
    let bundle = PreKeyBundleResponse {
        user_id,
        identity_key,
        signed_prekey: signed_prekey.prekey_public,
        signed_prekey_signature: signed_prekey.signature,
        one_time_prekey: otp.as_ref().map(|k| k.prekey_public.clone()),
        one_time_prekey_id: otp.as_ref().map(|k| k.id),
    };
    
    Ok(Json(bundle))
}

/// POST /keys/one-time
/// Загрузить One-Time PreKeys
pub async fn upload_one_time_prekeys(
    State(state): State<AppState>,
    CurrentUser { id, .. }: CurrentUser,
    Json(payload): Json<UploadPreKeysRequest>,
) -> Result<StatusCode, StatusCode> {
    let pool = &state.pool;
    
    // Валидация: не более 100 PreKeys за раз
    if payload.prekeys.len() > 100 {
        return Err(StatusCode::BAD_REQUEST);
    }
    
    // Вставка PreKeys
    for prekey in payload.prekeys {
        sqlx::query(
            "INSERT INTO prekeys (user_id, prekey_id, prekey_public) 
             VALUES ($1, $2, $3) 
             ON CONFLICT (user_id, prekey_id) DO NOTHING"
        )
        .bind(id)
        .bind(prekey.prekey_id)
        .bind(prekey.prekey)
        .execute(pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    }
    
    Ok(StatusCode::OK)
}

/// POST /keys/signed
/// Загрузить/обновить Signed PreKey
pub async fn upload_signed_prekey(
    State(state): State<AppState>,
    CurrentUser { id, .. }: CurrentUser,
    Json(payload): Json<UploadSignedPreKeyRequest>,
) -> Result<StatusCode, StatusCode> {
    let pool = &state.pool;
    
    // Валидация
    if payload.prekey.is_empty() || payload.signature.is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }
    
    // Пометить текущий Signed PreKey как неактивный
    sqlx::query(
        "UPDATE signed_prekeys SET is_current = FALSE WHERE user_id = $1"
    )
    .bind(id)
    .execute(pool)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    // Вставить новый Signed PreKey
    sqlx::query(
        "INSERT INTO signed_prekeys (user_id, prekey_public, signature, is_current) 
         VALUES ($1, $2, $3, TRUE)"
    )
    .bind(id)
    .bind(payload.prekey)
    .bind(payload.signature)
    .execute(pool)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    Ok(StatusCode::OK)
}

/// DELETE /keys/one-time/{prekey_id}
/// Пометить PreKey как использованный
pub async fn consume_prekey(
    State(state): State<AppState>,
    Path(prekey_id): Path<i32>,
) -> Result<StatusCode, StatusCode> {
    let pool = &state.pool;
    
    sqlx::query(
        "UPDATE prekeys SET used_at = NOW() WHERE id = $1 AND used_at IS NULL"
    )
    .bind(prekey_id)
    .execute(pool)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    Ok(StatusCode::OK)
}

/// Роутер для PreKey API
pub fn router() -> Router<AppState> {
    Router::new()
        .route("/keys/:user_id/bundle", get(get_prekey_bundle))
        .route("/keys/one-time", post(upload_one_time_prekeys))
        .route("/keys/signed", post(upload_signed_prekey))
        .route("/keys/one-time/:prekey_id", delete(consume_prekey))
}
