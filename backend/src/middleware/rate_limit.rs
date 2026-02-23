use axum::{
    extract::{Request, State},
    http::StatusCode,
    middleware::Next,
    response::Response,
};
use dashmap::DashMap;
use std::{
    sync::Arc,
    time::{Duration, Instant},
};

/// P1-7: Rate limiter middleware
/// 
/// Supports multiple bucketing strategies:
/// - IP-based: rate limit by client IP address
/// - Account-based: rate limit by user ID (after auth)
/// - Device-based: rate limit by device fingerprint

#[derive(Clone)]
pub struct RateLimiter {
    // IP-based buckets: IP -> (request_count, window_start)
    ip_buckets: Arc<DashMap<String, (u32, Instant)>>,
    
    // Account-based buckets: user_id -> (request_count, window_start)
    account_buckets: Arc<DashMap<i32, (u32, Instant)>>,
    
    // Configuration
    config: RateLimiterConfig,
}

#[derive(Clone)]
pub struct RateLimiterConfig {
    /// Maximum requests per window
    pub max_requests: u32,
    /// Window duration
    pub window_duration: Duration,
    /// Enable IP-based limiting
    pub enable_ip_limiting: bool,
    /// Enable account-based limiting (requires auth)
    pub enable_account_limiting: bool,
}

impl Default for RateLimiterConfig {
    fn default() -> Self {
        Self {
            max_requests: 100, // 100 requests per window
            window_duration: Duration::from_secs(60), // 1 minute window
            enable_ip_limiting: true,
            enable_account_limiting: false,
        }
    }
}

impl RateLimiter {
    pub fn new(config: RateLimiterConfig) -> Self {
        Self {
            ip_buckets: Arc::new(DashMap::new()),
            account_buckets: Arc::new(DashMap::new()),
            config,
        }
    }
    
    /// Check if request should be allowed based on IP
    pub fn check_ip_limit(&self, ip: &str) -> bool {
        if !self.config.enable_ip_limiting {
            return true;
        }
        
        let now = Instant::now();
        let mut entry = self.ip_buckets.entry(ip.to_string()).or_insert((0, now));
        
        // Check if window has expired
        if now.duration_since(entry.1) > self.config.window_duration {
            // Reset window
            *entry = (1, now);
            return true;
        }
        
        // Check if limit exceeded
        if entry.0 >= self.config.max_requests {
            return false;
        }
        
        // Increment counter
        entry.0 += 1;
        true
    }
    
    /// Check if request should be allowed based on user ID
    pub fn check_account_limit(&self, user_id: i32, max_requests: Option<u32>) -> bool {
        if !self.config.enable_account_limiting {
            return true;
        }
        
        let now = Instant::now();
        let limit = max_requests.unwrap_or(self.config.max_requests);
        
        let mut entry = self.account_buckets.entry(user_id).or_insert((0, now));
        
        // Check if window has expired
        if now.duration_since(entry.1) > self.config.window_duration {
            // Reset window
            *entry = (1, now);
            return true;
        }
        
        // Check if limit exceeded
        if entry.0 >= limit {
            return false;
        }
        
        // Increment counter
        entry.0 += 1;
        true
    }
    
    /// Cleanup old entries (call periodically)
    pub async fn cleanup(&self) {
        let now = Instant::now();
        
        // Cleanup IP buckets
        self.ip_buckets.retain(|_, (_, start)| {
            now.duration_since(*start) <= self.config.window_duration
        });
        
        // Cleanup account buckets
        self.account_buckets.retain(|_, (_, start)| {
            now.duration_since(*start) <= self.config.window_duration
        });
    }
}

/// P1-7: Strict rate limiter for auth endpoints
/// More restrictive limits for login/register/refresh
#[derive(Clone)]
pub struct AuthRateLimiter {
    // IP-based: IP -> (failed_attempts, lockout_until)
    ip_failures: Arc<DashMap<String, (u32, Option<Instant>)>>,
    
    // Account-based: user_id -> (failed_attempts, lockout_until)
    account_failures: Arc<DashMap<String, (u32, Option<Instant>)>>,
    
    config: AuthRateLimiterConfig,
}

#[derive(Clone)]
pub struct AuthRateLimiterConfig {
    /// Max failed attempts before lockout
    pub max_failures: u32,
    /// Initial lockout duration
    pub lockout_duration: Duration,
    /// Exponential backoff multiplier
    pub backoff_multiplier: u32,
    /// Maximum lockout duration
    pub max_lockout: Duration,
}

impl Default for AuthRateLimiterConfig {
    fn default() -> Self {
        Self {
            max_failures: 5, // 5 failed attempts
            lockout_duration: Duration::from_secs(60), // 1 minute initial lockout
            backoff_multiplier: 2, // Exponential backoff
            max_lockout: Duration::from_secs(3600), // Max 1 hour lockout
        }
    }
}

impl AuthRateLimiter {
    pub fn new(config: AuthRateLimiterConfig) -> Self {
        Self {
            ip_failures: Arc::new(DashMap::new()),
            account_failures: Arc::new(DashMap::new()),
            config,
        }
    }
    
    /// Record a failed authentication attempt
    /// Returns (allowed, lockout_seconds)
    pub fn record_failure(&self, ip: &str, account: Option<&str>) -> (bool, Option<u64>) {
        let now = Instant::now();
        
        // Check IP-based lockout
        if let Some(mut entry) = self.ip_failures.get_mut(ip) {
            if let Some(lockout_until) = entry.1 {
                if now < lockout_until {
                    let remaining = lockout_until.duration_since(now).as_secs();
                    return (false, Some(remaining));
                } else {
                    // Lockout expired, reset
                    entry.0 = 0;
                    entry.1 = None;
                }
            }
            
            entry.0 += 1;
            
            if entry.0 >= self.config.max_failures {
                // Calculate lockout with exponential backoff
                let backoff = self.config.lockout_duration.as_secs()
                    * (self.config.backoff_multiplier as u64).pow((entry.0 - self.config.max_failures).min(10));
                let lockout = Duration::from_secs(backoff.min(self.config.max_lockout.as_secs()));
                entry.1 = Some(now + lockout);
                
                return (false, Some(lockout.as_secs()));
            }
        } else {
            self.ip_failures.insert(ip.to_string(), (1, None));
        }
        
        // Check account-based lockout
        if let Some(account) = account {
            if let Some(mut entry) = self.account_failures.get_mut(account) {
                if let Some(lockout_until) = entry.1 {
                    if now < lockout_until {
                        let remaining = lockout_until.duration_since(now).as_secs();
                        return (false, Some(remaining));
                    } else {
                        entry.0 = 0;
                        entry.1 = None;
                    }
                }
                
                entry.0 += 1;
                
                if entry.0 >= self.config.max_failures {
                    let backoff = self.config.lockout_duration.as_secs()
                        * (self.config.backoff_multiplier as u64).pow((entry.0 - self.config.max_failures).min(10));
                    let lockout = Duration::from_secs(backoff.min(self.config.max_lockout.as_secs()));
                    entry.1 = Some(now + lockout);
                    
                    return (false, Some(lockout.as_secs()));
                }
            } else {
                self.account_failures.insert(account.to_string(), (1, None));
            }
        }
        
        (true, None)
    }
    
    /// Record a successful authentication - reset counters
    pub fn record_success(&self, ip: &str, account: Option<&str>) {
        self.ip_failures.remove(ip);
        if let Some(acc) = account {
            self.account_failures.remove(&acc.to_string());
        }
    }
    
    /// Check if request is allowed (without recording)
    pub fn is_allowed(&self, ip: &str, account: Option<&str>) -> bool {
        let now = Instant::now();
        
        // Check IP lockout
        if let Some(entry) = self.ip_failures.get(ip) {
            if let Some(lockout_until) = entry.1 {
                if now < lockout_until {
                    return false;
                }
            }
        }
        
        // Check account lockout
        if let Some(account) = account {
            if let Some(entry) = self.account_failures.get(&account.to_string()) {
                if let Some(lockout_until) = entry.1 {
                    if now < lockout_until {
                        return false;
                    }
                }
            }
        }
        
        true
    }
    
    /// Get remaining attempts for an IP/account
    pub fn get_remaining_attempts(&self, ip: &str, account: Option<&str>) -> u32 {
        let ip_remaining = self.ip_failures
            .get(ip)
            .map(|e| self.config.max_failures.saturating_sub(e.0))
            .unwrap_or(self.config.max_failures);
        
        let account_remaining = account
            .and_then(|acc| self.account_failures.get(acc))
            .map(|e| self.config.max_failures.saturating_sub(e.0))
            .unwrap_or(self.config.max_failures);
        
        ip_remaining.min(account_remaining)
    }
}

/// P1-7: Middleware for general rate limiting
pub async fn rate_limit_middleware(
    State(limiter): State<RateLimiter>,
    req: Request,
    next: Next,
) -> Result<Response, StatusCode> {
    // Extract IP from request
    let ip = req
        .extensions()
        .get::<axum::extract::ConnectInfo<std::net::SocketAddr>>()
        .map(|ci| ci.0.ip().to_string())
        .or_else(|| {
            req.headers()
                .get("x-forwarded-for")
                .and_then(|v| v.to_str().ok())
                .and_then(|s| s.split(',').next())
                .map(|s| s.trim().to_string())
        })
        .unwrap_or_else(|| "unknown".to_string());
    
    // Check IP-based rate limit
    if !limiter.check_ip_limit(&ip) {
        return Err(StatusCode::TOO_MANY_REQUESTS);
    }
    
    // Continue to next middleware/handler
    Ok(next.run(req).await)
}

/// P1-7: Middleware for strict auth rate limiting
pub async fn auth_rate_limit_middleware(
    State(limiter): State<AuthRateLimiter>,
    req: Request,
    next: Next,
) -> Result<Response, StatusCode> {
    // Extract IP
    let ip = req
        .extensions()
        .get::<axum::extract::ConnectInfo<std::net::SocketAddr>>()
        .map(|ci| ci.0.ip().to_string())
        .or_else(|| {
            req.headers()
                .get("x-forwarded-for")
                .and_then(|v| v.to_str().ok())
                .and_then(|s| s.split(',').next())
                .map(|s| s.trim().to_string())
        })
        .unwrap_or_else(|| "unknown".to_string());
    
    // Check if allowed
    if !limiter.is_allowed(&ip, None) {
        return Err(StatusCode::TOO_MANY_REQUESTS);
    }
    
    Ok(next.run(req).await)
}
