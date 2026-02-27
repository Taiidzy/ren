/// Symmetric Ratchet for Double Ratchet Protocol
///
/// This module handles the symmetric key ratchet that produces
/// message keys from chain keys through HMAC-SHA256 iterations.

use super::chain::{ChainKey, MessageKey, SkippedMessageKey};
use std::collections::HashMap;

/// Maximum number of skipped messages to store (защита от DoS)
const MAX_SKIPPED_KEYS: usize = 1000;

/// Symmetric Ratchet State
/// 
/// Управляет sending и receiving chain keys
#[derive(Debug, Clone)]
pub struct SymmetricRatchet {
    /// Sending chain key (для шифрования)
    pub sending_chain: Option<ChainKey>,
    /// Receiving chain key (для расшифровки)
    pub receiving_chain: Option<ChainKey>,
    /// Счётчик отправленных сообщений
    pub sent_message_count: u32,
    /// Счётчик полученных сообщений
    pub received_message_count: u32,
    /// Skipped message keys для out-of-order расшифровки
    pub skipped_keys: HashMap<String, Vec<SkippedMessageKey>>,
}

impl SymmetricRatchet {
    pub fn new() -> Self {
        Self {
            sending_chain: None,
            receiving_chain: None,
            sent_message_count: 0,
            received_message_count: 0,
            skipped_keys: HashMap::new(),
        }
    }

    /// Получить следующий message key для шифрования
    pub fn next_message_key(&mut self) -> Result<MessageKey, &'static str> {
        let chain_key = self.sending_chain.as_mut()
            .ok_or("No sending chain available")?;
        
        let message_key = chain_key.next();
        self.sent_message_count += 1;
        
        Ok(message_key)
    }

    /// Получить message key для расшифровки по counter
    /// 
    /// Поддерживает out-of-order сообщения через skipped keys storage
    pub fn get_message_key_for_counter(
        &mut self,
        ephemeral_key: &str,
        counter: u32,
    ) -> Result<MessageKey, &'static str> {
        // Проверяем skipped keys сначала
        if let Some(skipped_list) = self.skipped_keys.get_mut(ephemeral_key) {
            if let Some(pos) = skipped_list.iter().position(|k| k.counter == counter) {
                let skipped = skipped_list.remove(pos);
                return Ok(MessageKey::new(skipped.key, counter));
            }
        }

        // Если receiving chain ещё нет, ошибка
        let chain_key = self.receiving_chain.as_mut()
            .ok_or("No receiving chain available")?;

        // Если counter меньше текущего iteration, это старое сообщение — ошибка
        if counter < chain_key.iteration {
            return Err("Message counter is too old");
        }

        // Если counter больше, skip ahead и сохраняем skipped keys
        if counter > chain_key.iteration {
            // Сначала вычисляем сколько нужно пропустить
            let skip_count = (counter - chain_key.iteration) as usize;
            
            // Проверка на DoS
            if skip_count > MAX_SKIPPED_KEYS {
                return Err("Too many skipped messages");
            }

            // Skip до target_counter, сохраняя skipped keys
            let mut skipped = Vec::new();
            while chain_key.iteration < counter {
                let message_key = chain_key.next();
                skipped.push(SkippedMessageKey::new(
                    ephemeral_key.to_string(),
                    message_key.iteration,
                    *message_key.as_bytes(),
                ));
            }

            // Сохраняем skipped keys
            let skipped_list = self.skipped_keys.entry(ephemeral_key.to_string()).or_insert_with(Vec::new);
            skipped_list.extend(skipped);

            // Ограничиваем размер списка skipped keys
            if skipped_list.len() > MAX_SKIPPED_KEYS {
                skipped_list.drain(0..skipped_list.len() - MAX_SKIPPED_KEYS);
            }
        }

        // Получаем message key для текущего counter
        Ok(chain_key.next())
    }

    /// Установить sending chain
    pub fn set_sending_chain(&mut self, chain_key: ChainKey) {
        self.sending_chain = Some(chain_key);
    }

    /// Установить receiving chain
    pub fn set_receiving_chain(&mut self, chain_key: ChainKey) {
        self.receiving_chain = Some(chain_key);
    }

    /// Получить текущий sending counter
    pub fn get_sending_counter(&self) -> u32 {
        self.sent_message_count
    }

    /// Получить текущий receiving counter
    pub fn get_receiving_counter(&self) -> u32 {
        self.received_message_count
    }

    /// Проверить, нужно ли сделать DH ratchet
    /// Возвращает true если sending_chain ещё не создан
    pub fn needs_sending_chain(&self) -> bool {
        self.sending_chain.is_none()
    }

    /// Проверить, нужно ли сделать DH ratchet для receiving
    pub fn needs_receiving_chain(&self) -> bool {
        self.receiving_chain.is_none()
    }

    /// Сериализация состояния
    pub fn to_state(&self) -> SymmetricRatchetState {
        SymmetricRatchetState {
            sending_chain_key: self.sending_chain.as_ref().map(|c| {
                base64::Engine::encode(&base64::engine::general_purpose::STANDARD, c.get_key())
            }),
            sending_counter: self.sending_chain.as_ref().map(|c| c.iteration),
            receiving_chain_key: self.receiving_chain.as_ref().map(|c| {
                base64::Engine::encode(&base64::engine::general_purpose::STANDARD, c.get_key())
            }),
            receiving_counter: self.receiving_chain.as_ref().map(|c| c.iteration),
            sent_message_count: self.sent_message_count,
            received_message_count: self.received_message_count,
            skipped_keys: self.skipped_keys.iter().map(|(k, v)| {
                (k.clone(), v.iter().map(|s| {
                    super::chain::SkippedMessageKey {
                        ephemeral_key: s.ephemeral_key.clone(),
                        counter: s.counter,
                        key: s.key,
                    }
                }).collect())
            }).collect(),
        }
    }

    /// Десериализация состояния
    pub fn from_state(state: &SymmetricRatchetState) -> Self {
        let sending_chain = state.sending_chain_key.as_ref().map(|key_b64| {
            let key_bytes = base64::Engine::decode(&base64::engine::general_purpose::STANDARD, key_b64)
                .unwrap_or_default();
            let mut key_arr = [0u8; 32];
            key_arr.copy_from_slice(&key_bytes[..32.min(key_bytes.len())]);
            ChainKey::from_state(key_arr, state.sending_counter.unwrap_or(0))
        });

        let receiving_chain = state.receiving_chain_key.as_ref().map(|key_b64| {
            let key_bytes = base64::Engine::decode(&base64::engine::general_purpose::STANDARD, key_b64)
                .unwrap_or_default();
            let mut key_arr = [0u8; 32];
            key_arr.copy_from_slice(&key_bytes[..32.min(key_bytes.len())]);
            ChainKey::from_state(key_arr, state.receiving_counter.unwrap_or(0))
        });

        let skipped_keys = state.skipped_keys.iter().map(|(k, v)| {
            (k.clone(), v.iter().map(|s| {
                SkippedMessageKey::new(s.ephemeral_key.clone(), s.counter, s.key)
            }).collect())
        }).collect();

        Self {
            sending_chain,
            receiving_chain,
            sent_message_count: state.sent_message_count,
            received_message_count: state.received_message_count,
            skipped_keys,
        }
    }
}

impl Default for SymmetricRatchet {
    fn default() -> Self {
        Self::new()
    }
}

/// Сериализуемое состояние Symmetric Ratchet
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SymmetricRatchetState {
    pub sending_chain_key: Option<String>,
    pub sending_counter: Option<u32>,
    pub receiving_chain_key: Option<String>,
    pub receiving_counter: Option<u32>,
    pub sent_message_count: u32,
    pub received_message_count: u32,
    pub skipped_keys: HashMap<String, Vec<super::chain::SkippedMessageKey>>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::x3dh::SharedSecret;

    #[test]
    fn test_next_message_key() {
        let shared_secret = SharedSecret::new([42u8; 32]);
        let root_key = RootKey::new(*shared_secret.as_bytes());
        let (_, chain_key) = root_key.kdf(&[1u8; 32]);
        
        let mut ratchet = SymmetricRatchet::new();
        ratchet.set_sending_chain(chain_key);
        
        let key1 = ratchet.next_message_key().unwrap();
        let key2 = ratchet.next_message_key().unwrap();
        
        assert_ne!(key1.as_bytes(), key2.as_bytes());
        assert_eq!(ratchet.get_sending_counter(), 2);
    }

    #[test]
    fn test_out_of_order_message() {
        let shared_secret = SharedSecret::new([42u8; 32]);
        let root_key = RootKey::new(*shared_secret.as_bytes());
        let (_, chain_key) = root_key.kdf(&[1u8; 32]);
        
        let mut ratchet = SymmetricRatchet::new();
        ratchet.set_receiving_chain(chain_key);
        
        // Получаем key для counter 0
        let key0 = ratchet.get_message_key_for_counter("ephemeral", 0).unwrap();
        
        // Skip to counter 2 (out-of-order)
        let key2 = ratchet.get_message_key_for_counter("ephemeral", 2).unwrap();
        
        // Теперь counter 1 должно работать из skipped keys
        let key1 = ratchet.get_message_key_for_counter("ephemeral", 1).unwrap();
        
        assert_ne!(key0.as_bytes(), key1.as_bytes());
        assert_ne!(key1.as_bytes(), key2.as_bytes());
    }
}
