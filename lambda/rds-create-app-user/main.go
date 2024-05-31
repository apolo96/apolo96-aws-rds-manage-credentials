package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-lambda-go/lambdacontext"
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
	lc, ok := lambdacontext.FromContext(ctx)
	if !ok {
		fmt.Print("can't get lambda context")
	}
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	logger = logger.With("RequestId", lc.AwsRequestID)
	slog.SetDefault(logger)
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		err := fmt.Errorf("unable to load SDK config %v", err)
		slog.Error(err.Error())
		return "", err
	}
	svc := secretsmanager.NewFromConfig(cfg)
	secretLabel := fmt.Sprintf(
		"arn:aws:rds:%s:%s:db:%s",
		os.Getenv("AWS_REGION"),
		os.Getenv("AWS_ACCOUNT"),
		os.Getenv("DB_ID"),
	)
	slog.Info("secret tag " + secretLabel)
	secrets, err := getSecretByTag(ctx, svc, "aws:rds:primaryDBInstanceArn", secretLabel)
	if err != nil {
		slog.Error("failed to get master secret value", "error", err.Error(), "secret_name", secretLabel)
		return "", fmt.Errorf("failed to get master secret value: %v", err)
	}
	if secrets.Username == "" || secrets.Password == "" {
		err := fmt.Errorf("master credentials are empty")
		slog.Error(err.Error())
		return "", err
	}
	dsn := fmt.Sprintf("%s:%s@tcp(%s)/", secrets.Username, secrets.Password, os.Getenv("DB_HOST"))
	db, err := sql.Open("mysql", dsn)
	if err != nil {
		err := fmt.Errorf("failed to connect to database: %v", err)
		slog.Error(err.Error())
		return "", err
	}
	defer db.Close()
	err = db.Ping()
	if err != nil {
		err := fmt.Errorf("failed to ping database: %v", err)
		slog.Error(err.Error())
		return "", err
	}
	dbName := os.Getenv("DB_NAME")
	_, err = db.Exec(fmt.Sprintf("CREATE DATABASE IF NOT EXISTS %s", dbName))
	if err != nil {
		err := fmt.Errorf("failed to create database: %v", err)
		slog.Error(err.Error(), "database", dbName)
		return "", err
	}
	/* ADMIN DB USER */
	adminCreds, err := getSecret(ctx, svc, os.Getenv("DB_ADMIN_SECRET_KEY"))
	if err != nil {
		err := fmt.Errorf("failed to get admin secret value: %v", err)
		slog.Error(err.Error(), "secret_name", os.Getenv("DB_ADMIN_SECRET_KEY"))
		return "", err
	}
	if adminCreds.Username == "" || adminCreds.Password == "" {
		err := fmt.Errorf("admin credentials are empty")
		slog.Error(err.Error())
		return "", err
	}
	_, err = db.Exec(fmt.Sprintf("CREATE USER IF NOT EXISTS '%s'@'%%' IDENTIFIED BY '%s'", adminCreds.Username, adminCreds.Password))
	if err != nil {
		err := fmt.Errorf("failed to create admin user: %v", err)
		slog.Error(err.Error())
		return "", err
	}
	_, err = db.Exec(fmt.Sprintf("GRANT ALL PRIVILEGES ON %s.* TO '%s'@'%%'", dbName, adminCreds.Username))
	if err != nil {
		err := fmt.Errorf("failed to admin grant privileges: %v", err)
		slog.Error(err.Error())
		return "", err
	}
	/* APP DB USER */
	appCreds, err := getSecret(ctx, svc, os.Getenv("DB_APP_SECRET_KEY"))
	if err != nil {
		err := fmt.Errorf("failed to get app secret value: %v", err)
		slog.Error(err.Error(), "secret_name", os.Getenv("DB_APP_SECRET_KEY"))
		return "", err
	}
	if appCreds.Username == "" || appCreds.Password == "" {
		err := fmt.Errorf("app credentials are empty")
		slog.Error(err.Error())
		return "", err
	}
	_, err = db.Exec(fmt.Sprintf("CREATE USER IF NOT EXISTS '%s'@'%%' IDENTIFIED BY '%s'", appCreds.Username, appCreds.Password))
	if err != nil {
		err := fmt.Errorf("failed to create app user: %v", err)
		slog.Error(err.Error())
		return "", err
	}
	_, err = db.Exec(fmt.Sprintf("GRANT INSERT, UPDATE, DELETE, SELECT, REFERENCES ON %s.* TO '%s'@'%%'", dbName, appCreds.Username))
	if err != nil {
		err := fmt.Errorf("failed to grant privileges for app user: %v", err)
		slog.Error(err.Error())
		return "", err
	}
	_, err = db.Exec("FLUSH PRIVILEGES")
	if err != nil {
		err := fmt.Errorf("failed to flush privileges: %v", err)
		slog.Error(err.Error())
		return "", err
	}
	slog.Info("database and user created successfully")
	return "Database and user created successfully", nil
}

func main() {
	lambda.Start(handler)
}
