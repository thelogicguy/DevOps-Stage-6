# auth-api

This part of the application is responsible for authentication. It is written in Go and tested with Go1.21

It provides a single useful API endpoint `POST /login` that takes a simple JSON object and 
returns an access token in case of successful authentication.


## Prerequisites

- golang:1.21 

## ENV Configuration

The service scans environment for variables:
- `AUTH_API_PORT` - the port the service takes.
- `USERS_API_ADDRESS` - base URL of [Users API](/users-api).
- `JWT_SECRET` - secret value for JWT generator.

## Building and running without Docker

# Download all Go module dependencies
go mod download

# Build the auth-api binary with output name 'auth-api'
go build -o auth-api

# Run the application (Choose one of the following methods):

# Method 1: Run directly with environment variables inline
AUTH_API_PORT=8081 USERS_API_ADDRESS=http://users-api:8083 JWT_SECRET=your-secret-here ./auth-api

# Method 2: Source from .env file and run
source .env && ./auth-api

# Method 3: Run in development mode using go run
go run main.go

