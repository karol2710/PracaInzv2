#!/bin/bash
set -e

# =============================
# CONFIG
# =============================
PG_USER="deployer_user"
PG_PASSWORD="deployer_password"
PG_DB="deployer"
EXPORT_ENV_FOR="/etc/profile.d/deployer-db.sh"   # system-wide env variable

# =============================
# Root check
# =============================
if [[ $EUID -ne 0 ]]; then
  echo "Uruchom skrypt jako root"
  exit 1
fi

echo "==> Aktualizacja systemu"
apt update -y

echo "==> Instalacja PostgreSQL"
apt install -y postgresql postgresql-contrib

echo "==> Uruchamianie i włączanie usługi PostgreSQL"
systemctl enable postgresql
systemctl start postgresql

# =============================
# Tworzenie użytkownika & DB
# =============================
echo "==> Tworzenie użytkownika i bazy w PostgreSQL"

sudo -u postgres psql <<EOF
DO
\$do\$
BEGIN
   IF NOT EXISTS (
      SELECT FROM pg_catalog.pg_roles WHERE rolname = '${PG_USER}'
   ) THEN
      CREATE ROLE ${PG_USER} LOGIN PASSWORD '${PG_PASSWORD}';
   END IF;
END
\$do\$;

CREATE DATABASE ${PG_DB} OWNER ${PG_USER};
EOF

echo "==> Ustawianie zmiennej środowiskowej DATABASE_URL"

DATABASE_URL="postgresql://${PG_USER}:${PG_PASSWORD}@localhost:5432/${PG_DB}"

cat <<EOF > $EXPORT_ENV_FOR
export DATABASE_URL="${DATABASE_URL}"
EOF

chmod +x $EXPORT_ENV_FOR

echo "==> Ładowanie zmiennej środowiskowej"
source $EXPORT_ENV_FOR

# =============================
# Sprawdzenie działania
# =============================
echo "==> Sprawdzanie połączenia z bazą"
PGPASSWORD="${PG_PASSWORD}" psql -U "${PG_USER}" -d "${PG_DB}" -h localhost -c "SELECT 'Connection OK' AS status;"

echo ""
echo "========================================"
echo "🎉 Instalacja zakończona!"
echo "DATABASE_URL zostało ustawione na:"
echo "${DATABASE_URL}"
echo "Dostępne globalnie w systemie po restarcie powłoki."
echo "========================================"
