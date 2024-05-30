locals {
  function_name = "rds-create-user"
  src_path      = "${path.module}/lambda/${local.function_name}"

  binary_name  = local.function_name
  binary_path  = "${path.module}/tf_artifacts/${local.binary_name}"
  archive_path = "${path.module}/tf_artifacts/${local.function_name}.zip"
}