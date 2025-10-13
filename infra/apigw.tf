# HTTP API
resource "aws_apigatewayv2_api" "wake_api" {
  name          = "${var.project_name}-wake-api"
  protocol_type = "HTTP"
  # если нужен CORS с фронта на другом домене, раскомментируй:
  # cors_configuration {
  #   allow_headers = ["*"]
  #   allow_methods = ["GET", "POST", "OPTIONS"]
  #   allow_origins = ["*"]
  # }
}

# Интеграция с wake_instance (универсальная лямбда: /, /status, /heartbeat)
resource "aws_apigatewayv2_integration" "wake_integration" {
  api_id                 = aws_apigatewayv2_api.wake_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.wake_instance.invoke_arn
  payload_format_version = "2.0"
}

# (НЕ обязательно) Интеграция со sleep_instance — оставим только для ручного теста
resource "aws_apigatewayv2_integration" "sleep_integration" {
  api_id                 = aws_apigatewayv2_api.wake_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.sleep_instance.invoke_arn
  payload_format_version = "2.0"
}

# -------- РОУТЫ --------

# Корень — показывает страницу ожидания или редиректит, в зависимости от состояния
resource "aws_apigatewayv2_route" "root" {
  api_id    = aws_apigatewayv2_api.wake_api.id
  route_key = "ANY /"
  target    = "integrations/${aws_apigatewayv2_integration.wake_integration.id}"
}

# Проверка готовности (поллит JS со страницы ожидания)
resource "aws_apigatewayv2_route" "status" {
  api_id    = aws_apigatewayv2_api.wake_api.id
  route_key = "ANY /status"
  target    = "integrations/${aws_apigatewayv2_integration.wake_integration.id}"
}

# Сердцебиение (фронт пингует раз в минуту, чтобы не заснуть)
resource "aws_apigatewayv2_route" "heartbeat" {
  api_id    = aws_apigatewayv2_api.wake_api.id
  route_key = "ANY /heartbeat"
  target    = "integrations/${aws_apigatewayv2_integration.wake_integration.id}"
}

# (необязательно) Ручной вызов сна — лучше убрать в проде
resource "aws_apigatewayv2_route" "sleep_route" {
  count     = var.expose_sleep_route ? 1 : 0
  api_id    = aws_apigatewayv2_api.wake_api.id
  route_key = "GET /sleep"
  target    = "integrations/${aws_apigatewayv2_integration.sleep_integration.id}"
}

# Автостейдж по умолчанию
resource "aws_apigatewayv2_stage" "wake_stage" {
  api_id      = aws_apigatewayv2_api.wake_api.id
  name        = "$default"
  auto_deploy = true
}

# -------- PERMISSIONS --------

# Разрешаем API Gateway вызывать wake_instance на всех маршрутах
resource "aws_lambda_permission" "apigw_invoke_wake" {
  statement_id  = "AllowInvokeFromHttpApiWake"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.wake_instance.function_name
  principal     = "apigateway.amazonaws.com"
  # HTTP API execution_arn формата: arn:aws:execute-api:region:acct:api-id
  # /*/* покрывает любые методы и роуты этого API
  source_arn = "${aws_apigatewayv2_api.wake_api.execution_arn}/*/*"
}

# (необязательно) Разрешаем вызывать sleep_instance, если оставляешь /sleep
resource "aws_lambda_permission" "apigw_invoke_sleep" {
  count         = var.expose_sleep_route ? 1 : 0
  statement_id  = "AllowInvokeFromHttpApiSleep"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sleep_instance.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.wake_api.execution_arn}/*/*"
}