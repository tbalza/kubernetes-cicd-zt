#!/bin/bash

# Run Django collectstatic
echo "Collecting static files..."
python manage.py collectstatic --noinput --clear

# Apply database migrations
echo "Applying database migrations..."
python manage.py migrate

# Start Gunicorn server
echo "Starting Gunicorn server..."
exec gunicorn django_tailwind_todo.wsgi:application --bind 0.0.0.0:8000