-- RAG Chatbot Database Schema
-- Migration 001: Initial Schema with pgvector
--
-- This migration creates the core tables and indexes for the RAG chatbot system.
-- It sets up document storage and vector search capabilities.

-- =============================================================================
-- EXTENSIONS
-- =============================================================================

-- Enable pgvector extension for vector similarity search
CREATE EXTENSION IF NOT EXISTS vector;

-- =============================================================================
-- TABLES
-- =============================================================================

-- Documents table: stores metadata about uploaded documents
CREATE TABLE IF NOT EXISTS documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  filename TEXT NOT NULL,
  upload_date TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  file_type TEXT CHECK (file_type IN ('pdf', 'docx', 'txt')),
  metadata JSONB DEFAULT '{}'::jsonb,

  -- Useful metadata fields to store in JSONB:
  -- - file_size_bytes: int
  -- - page_count: int (for PDFs)
  -- - processing_status: 'pending' | 'processing' | 'completed' | 'failed'
  -- - processing_time_ms: int
  -- - chunk_count: int
  -- - error_message: text (if failed)

  CONSTRAINT documents_filename_not_empty CHECK (length(filename) > 0)
);

-- Chunks table: stores document chunks with vector embeddings
CREATE TABLE IF NOT EXISTS chunks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,

  -- Content fields
  content TEXT NOT NULL,
  contextual_content TEXT NOT NULL,

  -- Embedding (768 dimensions for Gemini text-embedding-004)
  embedding vector(768),

  -- Metadata
  metadata JSONB DEFAULT '{}'::jsonb,
  chunk_index INTEGER NOT NULL,

  -- Useful metadata fields to store in JSONB:
  -- - token_count: int
  -- - char_count: int
  -- - start_position: int (character position in original document)
  -- - end_position: int
  -- - section_title: text (if available)
  -- - page_number: int (for PDFs)

  -- Constraints
  CONSTRAINT chunks_content_not_empty CHECK (length(content) > 0),
  CONSTRAINT chunks_contextual_content_not_empty CHECK (length(contextual_content) > 0),
  CONSTRAINT chunks_index_non_negative CHECK (chunk_index >= 0),
  CONSTRAINT chunks_unique_index_per_document UNIQUE (document_id, chunk_index)
);

-- =============================================================================
-- INDEXES
-- =============================================================================

-- Index for vector similarity search using IVFFlat
-- Uses cosine distance for semantic similarity
-- Lists parameter = 100 is good for up to ~100k vectors
-- For larger datasets, consider: lists = sqrt(num_vectors)
CREATE INDEX IF NOT EXISTS chunks_embedding_idx
ON chunks
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);

-- Index for full-text search on content
-- Uses GIN index for fast text search
-- 'english' configuration provides stemming and stop words
CREATE INDEX IF NOT EXISTS chunks_content_fts_idx
ON chunks
USING gin(to_tsvector('english', content));

-- Index for filtering chunks by document
-- Useful when querying specific documents
CREATE INDEX IF NOT EXISTS chunks_document_id_idx
ON chunks(document_id);

-- Index for ordering chunks within a document
-- Useful for reconstructing document order
CREATE INDEX IF NOT EXISTS chunks_document_chunk_order_idx
ON chunks(document_id, chunk_index);

-- Index on document upload date for sorting
CREATE INDEX IF NOT EXISTS documents_upload_date_idx
ON documents(upload_date DESC);

-- =============================================================================
-- FUNCTIONS
-- =============================================================================

-- Function to search chunks using hybrid search (vector + full-text)
-- This function combines vector similarity and keyword matching
CREATE OR REPLACE FUNCTION hybrid_search(
  query_embedding vector(768),
  query_text text,
  match_count integer DEFAULT 30,
  similarity_threshold float DEFAULT 0.5
)
RETURNS TABLE (
  id uuid,
  document_id uuid,
  content text,
  contextual_content text,
  chunk_index integer,
  similarity float,
  relevance_score float,
  metadata jsonb
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    c.id,
    c.document_id,
    c.content,
    c.contextual_content,
    c.chunk_index,
    1 - (c.embedding <=> query_embedding) AS similarity,
    ts_rank(to_tsvector('english', c.content), plainto_tsquery('english', query_text)) AS relevance_score,
    c.metadata
  FROM chunks c
  WHERE
    -- Vector similarity filter
    (c.embedding <=> query_embedding) < (1 - similarity_threshold)
    OR
    -- Full-text search filter
    to_tsvector('english', c.content) @@ plainto_tsquery('english', query_text)
  ORDER BY
    -- Combine scores (weighted: 70% vector, 30% text)
    (0.7 * (1 - (c.embedding <=> query_embedding))) + (0.3 * ts_rank(to_tsvector('english', c.content), plainto_tsquery('english', query_text))) DESC
  LIMIT match_count;
END;
$$;

-- Function to get document statistics
CREATE OR REPLACE FUNCTION get_document_stats(doc_id uuid)
RETURNS TABLE (
  document_id uuid,
  filename text,
  chunk_count bigint,
  total_tokens integer,
  avg_chunk_size float
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    d.id AS document_id,
    d.filename,
    COUNT(c.id) AS chunk_count,
    SUM((c.metadata->>'token_count')::integer) AS total_tokens,
    AVG((c.metadata->>'token_count')::integer) AS avg_chunk_size
  FROM documents d
  LEFT JOIN chunks c ON d.id = c.document_id
  WHERE d.id = doc_id
  GROUP BY d.id, d.filename;
END;
$$;

-- =============================================================================
-- COMMENTS (Documentation)
-- =============================================================================

COMMENT ON TABLE documents IS 'Stores metadata for uploaded documents';
COMMENT ON TABLE chunks IS 'Stores document chunks with vector embeddings for RAG retrieval';

COMMENT ON COLUMN documents.id IS 'Unique identifier for the document';
COMMENT ON COLUMN documents.filename IS 'Original filename of the uploaded document';
COMMENT ON COLUMN documents.file_type IS 'Type of document: pdf, docx, or txt';
COMMENT ON COLUMN documents.metadata IS 'Additional metadata in JSON format';

COMMENT ON COLUMN chunks.id IS 'Unique identifier for the chunk';
COMMENT ON COLUMN chunks.document_id IS 'Reference to parent document';
COMMENT ON COLUMN chunks.content IS 'Original chunk content without context';
COMMENT ON COLUMN chunks.contextual_content IS 'Chunk content with document/section context added';
COMMENT ON COLUMN chunks.embedding IS '768-dimensional vector embedding from Gemini';
COMMENT ON COLUMN chunks.chunk_index IS 'Sequential position of chunk in document (0-indexed)';

COMMENT ON INDEX chunks_embedding_idx IS 'IVFFlat index for fast vector similarity search';
COMMENT ON INDEX chunks_content_fts_idx IS 'GIN index for full-text search capabilities';

COMMENT ON FUNCTION hybrid_search IS 'Combines vector similarity and full-text search for optimal retrieval';
COMMENT ON FUNCTION get_document_stats IS 'Returns statistics for a specific document';

-- =============================================================================
-- GRANTS (Optional: for production with RLS)
-- =============================================================================

-- For development, we disable Row Level Security
-- In production, you should enable RLS and create appropriate policies

ALTER TABLE documents DISABLE ROW LEVEL SECURITY;
ALTER TABLE chunks DISABLE ROW LEVEL SECURITY;

-- =============================================================================
-- VERIFICATION QUERIES
-- =============================================================================

-- Run these to verify the migration was successful:

-- Check pgvector extension
-- SELECT * FROM pg_extension WHERE extname = 'vector';

-- Check tables
-- SELECT table_name FROM information_schema.tables
-- WHERE table_schema = 'public' AND table_name IN ('documents', 'chunks');

-- Check indexes
-- SELECT indexname FROM pg_indexes
-- WHERE schemaname = 'public' AND tablename = 'chunks';

-- Test vector insertion and search
-- INSERT INTO documents (filename, file_type) VALUES ('test.pdf', 'pdf');
-- INSERT INTO chunks (document_id, content, contextual_content, embedding, chunk_index)
-- VALUES (
--   (SELECT id FROM documents WHERE filename = 'test.pdf'),
--   'Test content',
--   'Document: test.pdf\n\nTest content',
--   array_fill(0.1, ARRAY[768])::vector(768),
--   0
-- );

-- =============================================================================
-- MIGRATION COMPLETE
-- =============================================================================

DO $$
BEGIN
  RAISE NOTICE 'Migration 001_initial_schema.sql completed successfully!';
  RAISE NOTICE 'Tables created: documents, chunks';
  RAISE NOTICE 'Indexes created: 5 total (2 on chunks for search, 3 for performance)';
  RAISE NOTICE 'Functions created: hybrid_search, get_document_stats';
END $$;
