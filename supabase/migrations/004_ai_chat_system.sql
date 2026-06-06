-- ── Chat sessions ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS chat_sessions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title           VARCHAR(200) DEFAULT 'New conversation',
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  last_message_at TIMESTAMPTZ DEFAULT NOW(),
  is_active       BOOLEAN DEFAULT TRUE
);

CREATE INDEX idx_chat_sessions_user ON chat_sessions(user_id);

ALTER TABLE chat_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY chat_sessions_user ON chat_sessions
  FOR ALL USING (auth.uid() = user_id);

-- ── Chat messages ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS chat_messages (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id  UUID NOT NULL REFERENCES chat_sessions(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role        VARCHAR(10) NOT NULL CHECK (role IN ('user', 'assistant')),
  content     TEXT NOT NULL,
  metadata    JSONB DEFAULT '{}',
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_chat_messages_session ON chat_messages(session_id, created_at);
CREATE INDEX idx_chat_messages_user    ON chat_messages(user_id);

ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY chat_messages_user ON chat_messages
  FOR ALL USING (auth.uid() = user_id);

-- ── Upgrade ai_insights: allow multiple per week, add priority ──
ALTER TABLE ai_insights
  ADD COLUMN IF NOT EXISTS priority     VARCHAR(15) DEFAULT 'informational',
  ADD COLUMN IF NOT EXISTS is_read      BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS is_dismissed BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS trigger_type VARCHAR(20) DEFAULT 'scheduled';

-- Drop the one-per-week constraint to allow multiple insights
ALTER TABLE ai_insights DROP CONSTRAINT IF EXISTS ai_insights_user_id_week_number_year_key;

-- Service role can insert chat messages (for assistant responses)
CREATE POLICY chat_messages_service_insert ON chat_messages
  FOR INSERT TO service_role WITH CHECK (true);
CREATE POLICY chat_sessions_service_all ON chat_sessions
  FOR ALL TO service_role USING (true);
