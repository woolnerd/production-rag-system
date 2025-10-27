# Database Setup Guide

This guide explains how to set up the Supabase database with pgvector for the RAG chatbot.

## Prerequisites

- Supabase account (https://supabase.com)
- Supabase project created

## Setup Steps

### 1. Create a Supabase Project

1. Go to https://app.supabase.com
2. Click "New Project"
3. Choose your organization
4. Enter project details:
   - Name: `rag-chatbot-demo`
   - Database Password: (generate a strong password)
   - Region: Choose closest to your users
5. Click "Create new project"
6. Wait for the project to be provisioned (~2 minutes)

### 2. Get Your Project Credentials

Once the project is ready:

1. Go to **Project Settings** > **API**
2. Copy the following:
   - **Project URL**: `https://your-project-id.supabase.co`
   - **anon public key**: Your `SUPABASE_KEY`
3. Add these to your `.env` file:

```env
SUPABASE_URL=https://your-project-id.supabase.co
SUPABASE_KEY=your-anon-public-key-here
```

### 3. Run Database Migration

Go to the **SQL Editor** in your Supabase dashboard and run the migration script:

1. Click **SQL Editor** in the left sidebar
2. Click **New query**
3. Copy and paste the contents of `migrations/001_initial_schema.sql`
4. Click **Run** or press `Cmd/Ctrl + Enter`

The migration will:
- Enable the `pgvector` extension
- Create `documents` table
- Create `chunks` table with vector embeddings
- Add necessary indexes for fast search

### 4. Verify the Setup

Run this verification query in the SQL Editor:

```sql
-- Check that pgvector is enabled
SELECT * FROM pg_extension WHERE extname = 'vector';

-- Check tables exist
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
AND table_name IN ('documents', 'chunks');

-- Check indexes
SELECT indexname
FROM pg_indexes
WHERE schemaname = 'public'
AND tablename = 'chunks';
```

You should see:
- ✅ pgvector extension enabled
- ✅ Two tables: `documents`, `chunks`
- ✅ Two indexes on chunks: one for vector search, one for full-text search

## Schema Details

### Documents Table

Stores metadata about uploaded documents.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| filename | text | Original filename |
| upload_date | timestamp | When uploaded |
| file_type | text | PDF, DOCX, or TXT |
| metadata | jsonb | Additional metadata |

### Chunks Table

Stores document chunks with embeddings.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| document_id | uuid | Foreign key to documents |
| content | text | Original chunk content |
| contextual_content | text | Content with metadata prefix |
| embedding | vector(768) | Gemini embedding |
| metadata | jsonb | Additional metadata |
| chunk_index | int | Position in document |

### Indexes

1. **Vector Index** (`chunks_embedding_idx`):
   - Type: IVFFlat
   - Metric: Cosine similarity
   - Used for: Semantic search

2. **Full-Text Index** (`chunks_content_fts_idx`):
   - Type: GIN
   - Used for: Keyword search

## Performance Tuning

### IVFFlat Index Configuration

The default IVFFlat configuration uses 100 lists. Tune this based on your data size:

```sql
-- For small datasets (< 10k chunks): lists = 100 (default)
-- For medium datasets (10k-100k chunks): lists = sqrt(num_chunks)
-- For large datasets (> 100k chunks): lists = sqrt(num_chunks)

-- Example: Re-create index with custom lists parameter
DROP INDEX chunks_embedding_idx;
CREATE INDEX chunks_embedding_idx
ON chunks
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 500);
```

### Query Performance

Enable query timing to monitor performance:

```sql
-- Enable timing
\timing on

-- Test vector search performance
EXPLAIN ANALYZE
SELECT id, content, 1 - (embedding <=> '[0.1, 0.2, ...]'::vector) AS similarity
FROM chunks
ORDER BY embedding <=> '[0.1, 0.2, ...]'::vector
LIMIT 30;
```

Target query time: < 100ms for vector search with proper indexing.

## Backup and Restore

### Create Backup

```bash
# Using Supabase CLI
supabase db dump -f backup.sql

# Or use pg_dump directly
pg_dump -h db.your-project.supabase.co \
  -U postgres \
  -d postgres \
  -f backup.sql
```

### Restore from Backup

```bash
# Using psql
psql -h db.your-project.supabase.co \
  -U postgres \
  -d postgres \
  -f backup.sql
```

## Troubleshooting

### pgvector Extension Not Found

If you get an error that `vector` extension doesn't exist:

1. Check Supabase project version (must be v2+)
2. Contact Supabase support to enable pgvector
3. Alternatively, use a self-hosted PostgreSQL with pgvector installed

### Slow Vector Queries

If vector search is slow (> 500ms):

1. Ensure the IVFFlat index exists: `\di chunks_embedding_idx`
2. Increase lists parameter (see Performance Tuning section)
3. Run `VACUUM ANALYZE chunks;` to update statistics
4. Consider upgrading Supabase plan for more resources

### Connection Issues

If you can't connect from the application:

1. Verify `SUPABASE_URL` and `SUPABASE_KEY` in `.env`
2. Check Row Level Security (RLS) is disabled for development
3. Ensure IP is not blocked in Supabase Network settings
4. Test connection with: `python -c "from supabase import create_client; create_client('URL', 'KEY')"`

## Security Considerations

### Development

For local development, you can disable Row Level Security (RLS):

```sql
ALTER TABLE documents DISABLE ROW LEVEL SECURITY;
ALTER TABLE chunks DISABLE ROW LEVEL SECURITY;
```

### Production

For production, enable RLS and create policies:

```sql
-- Enable RLS
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE chunks ENABLE ROW LEVEL SECURITY;

-- Example policy: Allow authenticated users to access their documents
CREATE POLICY "Users can access their own documents"
ON documents
FOR ALL
USING (auth.uid() = user_id);  -- Add user_id column first

CREATE POLICY "Users can access chunks of their documents"
ON chunks
FOR ALL
USING (
  document_id IN (
    SELECT id FROM documents WHERE user_id = auth.uid()
  )
);
```

## Monitoring

### Check Table Sizes

```sql
SELECT
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

### Monitor Query Performance

```sql
-- Enable pg_stat_statements extension
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- View slow queries
SELECT
  query,
  calls,
  mean_exec_time,
  max_exec_time
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```

## Next Steps

After completing the database setup:

1. ✅ Test connection from the application
2. ✅ Upload a test document
3. ✅ Verify chunks are stored with embeddings
4. ✅ Test vector and full-text search queries

---

For issues or questions, consult the [Supabase documentation](https://supabase.com/docs) or [pgvector documentation](https://github.com/pgvector/pgvector).
