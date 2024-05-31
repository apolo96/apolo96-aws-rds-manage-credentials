locals {
  function_name = "bootstrap"
  src_path      = "${path.module}/lambda/rds-create-app-user"

  binary_name  = local.function_name
  binary_path  = "${local.src_path}/bin/${local.binary_name}"
  archive_path = "${local.src_path}/${substr(filesha256("${local.src_path}/main.go"), 0, 10)}.zip"
}