# Use the official Python image as a base image
FROM python:3.12

# Set environment variables to prevent Python from writing pyc files to disc (optional)
ENV PYTHONDONTWRITEBYTECODE 1
# Prevent Python from buffering stdout and stderr, get real-time logs
ENV PYTHONUNBUFFERED 1

# Set the working directory in the container
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y libpq-dev && rm -rf /var/lib/apt/lists/*

# Copy the current directory contents into the container at /app with appropriate ownership
COPY . /app

# Install Python dependencies
RUN pip install --upgrade pip && pip install -r requirements.txt

# Make port 8000 available to the world outside this container
EXPOSE 8000

## Switch to non-root user
#USER ${USERNAME}
# Required for gunicorn
#ENV PATH="/home/myuser/.local/bin:${PATH}"

# Add execution permissions to the entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Use entrypoint to run collectstatic and start the server
ENTRYPOINT ["/entrypoint.sh"]

# https://liberbear.com/posts/python-nonroot-dockerfile/