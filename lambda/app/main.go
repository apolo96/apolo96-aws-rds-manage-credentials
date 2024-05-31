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
	_ "github.com/go-sql-driver/mysql"
)

type Secrets struct {
	Username string `json:"username"`
	Password string `json:"password"`
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
		fmt.Print("can not get lambda context")
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
	secrets, err := getSecret(ctx, svc, os.Getenv("DB_APP_SECRET_KEY"))
	if err != nil {
		slog.Error("failed to get app secret value", "error", err.Error(), "secret_name", os.Getenv("DB_APP_SECRET_KEY"))
		return "", fmt.Errorf("failed to get app db secret value: %v", err)
	}
	if secrets.Username == "" || secrets.Password == "" {
		err := fmt.Errorf("admin credentials are empty")
		slog.Error(err.Error())
		return "", err
	}
	dsn := fmt.Sprintf("%s:%s@tcp(%s)/%s", secrets.Username, secrets.Password, os.Getenv("DB_HOST"), os.Getenv("DB_NAME"))
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
	insertSQL := `
	INSERT INTO dragon (name)
	VALUES 
		('Alice'),
		('Bob'),
		('Charlie');
	`
	_, err = db.Exec(insertSQL)
	if err != nil {
		err := fmt.Errorf("failed to create data: %v", err)
		slog.Error(err.Error())
		return "", err
	}
	rows, err := db.Query("SELECT * FROM dragon")
	if err != nil {
		err := fmt.Errorf("failed to read data: %v", err)
		slog.Error(err.Error())
		return "", err
	}
	defer rows.Close()
	for rows.Next() {
		var id int
		var name string
		var createdAt string
		err := rows.Scan(&id, &name, &createdAt)
		if err != nil {
			err := fmt.Errorf("scanning data row: %v", err)
			slog.Error(err.Error())
		}
		fmt.Printf("ID: %d, Name: %s, CreatedAt: %s\n", id, name, createdAt)
	}
	slog.Info("app operations successfully")
	return "app operations successfully", nil
}

func main() {
	lambda.Start(handler)
}
