# =============================
# PROVIDER CONFIGURATION
# =============================
provider "aws" {
  region = "us-east-1"  # Change to your desired AWS region
}

# =============================
# DYNAMODB TABLE
# =============================
resource "aws_dynamodb_table" "visitor_counter" {
  name         = "VisitorCounter"  
  billing_mode = "PAY_PER_REQUEST"  # On-demand pricing (no capacity planning)

  hash_key = "id"  # Primary key (String)

  attribute {
    name = "id"  
    type = "S"  
  }

  attribute {
    name = "count"  
    type = "N"  
  }

  # ✅ Add a Global Secondary Index for "count"
  global_secondary_index {
    name               = "CountIndex"  # Name of the index
    hash_key           = "count"       # Indexing count as a key
    projection_type    = "ALL"         # Project all attributes
  }

  # Optional: Enable DynamoDB Streams (if needed)
  stream_enabled   = false
  stream_view_type = "NEW_IMAGE"
}

# =============================
# IAM ROLE FOR LAMBDA FUNCTION
# =============================
resource "aws_iam_role" "lambda_role" {
  name = "lambda-execution-role"

  assume_role_policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "lambda.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
      }
    ]
  }
  EOF
}

# IAM policy for Lambda to access DynamoDB
resource "aws_iam_policy" "lambda_policy" {
  name        = "LambdaDynamoDBPolicy"
  description = "IAM policy for Lambda to access DynamoDB"

  policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Scan"
        ],
        "Resource": "${aws_dynamodb_table.visitor_counter.arn}"
      }
    ]
  }
  EOF
}

# Attach the IAM policy to the role
resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# =============================
# LAMBDA FUNCTION (JAVASCRIPT)
# =============================
resource "aws_lambda_function" "resume_lambda" {
  function_name = "resumeLambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"  # Ensure this matches your index.js entry point
  runtime       = "nodejs18.x"

  filename         = "lambda.zip"  # Ensure this ZIP contains your index.js
  source_code_hash = filebase64sha256("lambda.zip")

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.visitor_counter.name
    }
  }
}

# =============================
# API GATEWAY
# =============================
resource "aws_apigatewayv2_api" "resume_api" {
  name          = "resumeApi"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.resume_api.id
  name        = "$default"
  auto_deploy = true
}

# API Gateway integration with Lambda
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.resume_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.resume_lambda.invoke_arn
}

# Define API Gateway Route (Modify "GET /resume" if needed)
resource "aws_apigatewayv2_route" "lambda_route" {
  api_id    = aws_apigatewayv2_api.resume_api.id
  route_key = "GET /resume"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Allow API Gateway to invoke Lambda function
resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.resume_lambda.function_name
  principal     = "apigateway.amazonaws.com"
}

# =============================
# OUTPUTS
# =============================
output "api_gateway_url" {
  value       = aws_apigatewayv2_api.resume_api.api_endpoint
  description = "The base URL of the deployed API Gateway"
}
