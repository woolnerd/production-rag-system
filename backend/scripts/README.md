# Maintenance Scripts

Utility scripts for database maintenance and demo management.

## cleanup_demo.py

Automated cleanup script that deletes old documents and associated data from the database.

### Purpose

- Prevents database bloat in demo environment
- Removes documents older than 24 hours by default
- Cascades deletion to associated chunks and embeddings
- Protects global documents by default

### Usage

#### Basic Usage

```bash
# From backend directory
cd backend
python scripts/cleanup_demo.py
```

#### Command Line Options

```bash
# Show help
python scripts/cleanup_demo.py --help

# Dry run (show what would be deleted without deleting)
python scripts/cleanup_demo.py --dry-run

# Custom time threshold (delete older than 48 hours)
python scripts/cleanup_demo.py --hours 48

# Include global documents in cleanup (dangerous!)
python scripts/cleanup_demo.py --include-global

# Combine options
python scripts/cleanup_demo.py --hours 12 --dry-run
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `--hours N` | 24 | Delete documents older than N hours |
| `--dry-run` | False | Preview deletions without actually deleting |
| `--include-global` | False | Include global documents (normally excluded) |

### Output Example

```
🧹 Starting cleanup for documents older than 24 hours...
   Cutoff time: 2025-11-09T16:30:00+00:00
   Dry run: No
   Exclude global docs: Yes

📋 Found 15 documents to delete:

   ✓ Deleted: electricity-bill.pdf (age: 26.3h, 12 chunks, session: a1b2c3d4...)
   ✓ Deleted: contract.docx (age: 30.1h, 8 chunks, session: e5f6g7h8...)
   ✓ Deleted: notes.txt (age: 48.5h, 3 chunks, session: i9j0k1l2...)
   ...

============================================================
🎉 CLEANUP COMPLETE
Deleted: 15/15 documents
Total chunks: 156
Sessions affected: 8
============================================================

📊 Final Statistics:
   Documents found: 15
   Documents deleted: 15
   Chunks deleted: 156
   Sessions affected: 8
```

### Automated Scheduling

#### Option 1: Cron Job (Linux/Mac)

```bash
# Edit crontab
crontab -e

# Run daily at 2 AM
0 2 * * * cd /path/to/rag-demo/backend && /path/to/venv/bin/python scripts/cleanup_demo.py >> /var/log/rag-cleanup.log 2>&1

# Run every 6 hours
0 */6 * * * cd /path/to/rag-demo/backend && /path/to/venv/bin/python scripts/cleanup_demo.py >> /var/log/rag-cleanup.log 2>&1

# Run every 12 hours
0 */12 * * * cd /path/to/rag-demo/backend && /path/to/venv/bin/python scripts/cleanup_demo.py >> /var/log/rag-cleanup.log 2>&1
```

**Important**: Use absolute paths in cron jobs!

#### Option 2: Systemd Timer (Linux)

Create `/etc/systemd/system/rag-cleanup.service`:

```ini
[Unit]
Description=RAG Demo Cleanup Service
After=network.target

[Service]
Type=oneshot
User=your-user
WorkingDirectory=/path/to/rag-demo/backend
Environment="PATH=/path/to/venv/bin:/usr/bin:/bin"
ExecStart=/path/to/venv/bin/python scripts/cleanup_demo.py
StandardOutput=journal
StandardError=journal
```

Create `/etc/systemd/system/rag-cleanup.timer`:

```ini
[Unit]
Description=Run RAG cleanup daily
Requires=rag-cleanup.service

[Timer]
OnCalendar=daily
OnCalendar=02:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable and start:

```bash
sudo systemctl enable rag-cleanup.timer
sudo systemctl start rag-cleanup.timer
sudo systemctl status rag-cleanup.timer
```

#### Option 3: Docker Compose (for containerized deployments)

Add to `docker-compose.prod.yml`:

```yaml
services:
  cleanup:
    build: ./backend
    command: >
      sh -c "
        while true; do
          echo '🧹 Running cleanup...'
          python scripts/cleanup_demo.py
          echo '💤 Sleeping for 6 hours...'
          sleep 21600
        done
      "
    environment:
      - POSTGRES_HOST=${POSTGRES_HOST}
      - POSTGRES_PORT=${POSTGRES_PORT}
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    depends_on:
      - postgres
    restart: unless-stopped
```

### Log Management

#### View Cron Logs

```bash
# View cleanup log
tail -f /var/log/rag-cleanup.log

# View last 100 lines
tail -100 /var/log/rag-cleanup.log

# View logs with timestamps
tail -f /var/log/rag-cleanup.log | while read line; do echo "$(date): $line"; done
```

#### Log Rotation

Create `/etc/logrotate.d/rag-cleanup`:

```
/var/log/rag-cleanup.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 your-user your-user
}
```

### Monitoring

#### Check Cleanup Status

```bash
# Check last run time (cron)
grep "CLEANUP COMPLETE" /var/log/rag-cleanup.log | tail -1

# Check systemd timer status
systemctl status rag-cleanup.timer

# View recent cleanup runs
journalctl -u rag-cleanup.service -n 50
```

#### Database Size Monitoring

```bash
# Check database size
psql -U rag_user -d rag_db -c "
SELECT
    pg_size_pretty(pg_database_size('rag_db')) as db_size,
    (SELECT COUNT(*) FROM documents) as doc_count,
    (SELECT COUNT(*) FROM chunks) as chunk_count;
"
```

### Safety Features

1. **Global Document Protection**: By default, excludes documents with `session_id='global'`
2. **Dry Run Mode**: Test before deleting with `--dry-run`
3. **Cascade Deletion**: Automatically removes associated chunks (database foreign key)
4. **Transaction Safety**: Each deletion is atomic
5. **Error Handling**: Failed deletions are logged but don't stop the script
6. **Statistics**: Comprehensive reporting of what was deleted

### Troubleshooting

#### Script Won't Run

```bash
# Check permissions
chmod +x backend/scripts/cleanup_demo.py

# Check Python path
which python
python --version

# Run with absolute path
/path/to/venv/bin/python /path/to/backend/scripts/cleanup_demo.py
```

#### Database Connection Errors

```bash
# Verify environment variables
env | grep POSTGRES

# Test database connection
psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT 1;"
```

#### No Documents Being Deleted

```bash
# Check document ages
psql -U rag_user -d rag_db -c "
SELECT
    filename,
    upload_date,
    EXTRACT(EPOCH FROM (NOW() - upload_date))/3600 as age_hours,
    session_id
FROM documents
ORDER BY upload_date DESC
LIMIT 10;
"

# Run with dry-run to see what would be deleted
python scripts/cleanup_demo.py --dry-run
```

### Related

- Issue #70: Add automated cleanup cron job
- Issue #69: Session isolation implementation
- CLAUDE.md: Project documentation
