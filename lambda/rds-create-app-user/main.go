package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager/types"
	_ "github.com/go-sql-driver/mysql"
)

type Secrets struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

func getSecretByTag(ctx context.Context, svc *secretsmanager.Client, tagKey, tagValue string) (Secrets, error) {
	input := &secretsmanager.ListSecretsInput{
		Filters: []types.Filter{
			{
				Key:    types.FilterNameStringTypeTagValue,
				Values: []string{tagKey, tagValue},
			},
		},
	}
	result, err := svc.ListSecrets(ctx, input)
	if err != nil {
		return Secrets{}, err
	}
	for _, secret := range result.SecretList {
		fmt.Printf("Found secret: %s\n", *secret.Name)
	}
	var secret Secrets
	if len(result.SecretList) > 0 {
		secretId := *result.SecretList[0].Name
		secret, err = getSecret(ctx, svc, secretId)
		if err != nil {
			return Secrets{}, err
		}
	}
	return secret, nil
}

func getSecret(ctx context.Context, svc *secretsmanager.Client, secretName string) (Secrets, error) {
	input := &secretsmanager.GetSecretValueInput{
		SecretId: aws.String(secretName),
	}
	result, err := svc.GetSecretValue(ctx, input)
	if err != nil {
		return Secrets{}, err
	}
	var secret Secrets
	err = json.Unmarshal([]byte(*result.SecretString), &secret)
	if err != nil {
		return Secrets{}, err
	}

	return secret, nil
}

func handler(ctx context.Context) (string, error) {
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		slog.Error("unable to load SDK config", "error", err.Error())
	}
	svc := secretsmanager.NewFromConfig(cfg)
	slog.Info("Environment vars", "envs", fmt.Sprint(
		os.Getenv("AWS_REGION"),
		os.Getenv("AWS_ACCOUNT"),
		os.Getenv("DB_ID"),
		os.Getenv("DB_HOST"),
		os.Getenv("DB_NAME"),
		os.Getenv("DB_ADMIN_SECRET_KEY"),
	))
	secretLabel := fmt.Sprintf(
		"arn:aws:rds:%s:%s:db:%s",
		os.Getenv("AWS_REGION"),
		os.Getenv("AWS_ACCOUNT"),
		os.Getenv("DB_ID"),
	)
	slog.Info("Secret Tag " + secretLabel)
	secrets, err := getSecretByTag(ctx, svc, "aws:rds:primaryDBInstanceArn", secretLabel)
	if err != nil {
		return "", fmt.Errorf("failed to get secret: %v", err)
	}
	if secrets.Username == "" || secrets.Password == "" {
		return "", fmt.Errorf("master credentials are empty: %v", err)
	}
	dsn := fmt.Sprintf("%s:%s@tcp(%s)/", secrets.Username, secrets.Password, os.Getenv("DB_HOST"))
	db, err := sql.Open("mysql", dsn)
	if err != nil {
		return "", fmt.Errorf("failed to connect to database: %v", err)
	}
	defer db.Close()
	err = db.Ping()
	if err != nil {
		return "", fmt.Errorf("failed to ping database: %v", err)
	}
	dbName := os.Getenv("DB_NAME")
	_, err = db.Exec(fmt.Sprintf("CREATE DATABASE IF NOT EXISTS %s", dbName))
	if err != nil {
		return "", fmt.Errorf("failed to create database: %v", err)
	}
	adminCreds, err := getSecret(ctx, svc, os.Getenv("DB_ADMIN_SECRET_KEY"))
	if err != nil {
		return "", fmt.Errorf("failed to get secret value: %v", err)
	}
	if adminCreds.Username == "" || adminCreds.Password == "" {
		return "", fmt.Errorf("admin credentials are empty: %v", err)
	}
	_, err = db.Exec(fmt.Sprintf("CREATE USER IF NOT EXISTS '%s'@'%%' IDENTIFIED BY '%s'", adminCreds.Username, adminCreds.Password))
	if err != nil {
		return "", fmt.Errorf("failed to create user: %v", err)
	}
	_, err = db.Exec(fmt.Sprintf("GRANT ALL PRIVILEGES ON %s.* TO '%s'@'%%'", dbName, adminCreds.Username))
	if err != nil {
		return "", fmt.Errorf("failed to grant privileges: %v", err)
	}
	_, err = db.Exec("FLUSH PRIVILEGES")
	if err != nil {
		return "", fmt.Errorf("failed to flush privileges: %v", err)
	}
	return "Database and user created successfully", nil
}

func main() {
	lambda.Start(handler)
}
