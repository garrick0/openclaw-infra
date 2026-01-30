{
  "gateway": {
    "port": ${gateway_port},
    "mode": "local",
    "bind": "${gateway_bind}",
    "auth": {
      "mode": "token",
      "token": "${gateway_token}"
    }
  },
  "channels": {
    "whatsapp": {
      "dmPolicy": "allowlist",
      "selfChatMode": true,
      "allowFrom": [],
      "groupPolicy": "allowlist",
      "mediaMaxMb": 50,
      "debounceMs": 0
    }
  },
  "plugins": {
    "entries": {
      "whatsapp": {
        "enabled": true
      }
    }
  },
  "agents": {
    "defaults": {
      "workspace": "/mnt/data/openclaw/workspace",
      "maxConcurrent": 4
    }
  }
}
