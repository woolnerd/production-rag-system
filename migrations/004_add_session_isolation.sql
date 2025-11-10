-- Migration 004: Add session isolation support
-- Description: Add session_id column to documents table to support multi-user session isolation

-- Add session_id column to documents table
ALTER TABLE documents
ADD COLUMN session_id VARCHAR(255) NOT NULL DEFAULT 'global';

-- Create index on session_id for faster filtering
CREATE INDEX idx_documents_session_id ON documents(session_id);

-- Update existing documents to use 'global' session_id (default documents visible to all)
UPDATE documents SET session_id = 'global' WHERE session_id IS NULL;

-- Comments for documentation
COMMENT ON COLUMN documents.session_id IS 'Session identifier for multi-user isolation. Use "global" for documents visible to all users.';
COMMENT ON INDEX idx_documents_session_id IS 'Index for efficient session-based document filtering';

-- Verification query (optional, for testing)
-- SELECT session_id, COUNT(*) as doc_count
-- FROM documents
-- GROUP BY session_id;
