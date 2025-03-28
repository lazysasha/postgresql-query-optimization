# Postgres Query Optimization

## Setting up a database

1. Download DB backup file from https://drive.google.com/file/d/1lvn-10AI6__UX2--xlozz961EVt9GYbH/view?usp=sharing
2. run `docker-compose up`
3. Restore the data
```bash
docker exec -i postgresql-query-optimization-db-1 pg_restore -U postgres -v -d postgres < /Users/sshynkariuk/Downloads/postgres_air.backup
```
