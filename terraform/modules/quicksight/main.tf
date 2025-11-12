# ============================================================================
# QuickSight Module - Visualization Layer
# ============================================================================
# Provisions Amazon QuickSight account resources and connects to Athena

locals {
  # resource_prefix already includes environment (e.g., "flight-delays-dev"), so don't add it again
  authors_group_name = var.authors_group_name != "" ? var.authors_group_name : "${var.resource_prefix}-authors"
  readers_group_name = var.readers_group_name != "" ? var.readers_group_name : "${var.resource_prefix}-readers"
  data_source_id     = var.data_source_id != "" ? var.data_source_id : "${var.resource_prefix}-athena-ds"
  data_source_name   = var.data_source_name != "" ? var.data_source_name : "${var.resource_prefix}-athena"
}

# ----------------------------------------------------------------------------
# Optional QuickSight Account Subscription (run once per AWS account)
# ----------------------------------------------------------------------------

resource "aws_quicksight_account_subscription" "this" {
  count = var.create_account_subscription ? 1 : 0

  account_name          = var.quicksight_account_name
  authentication_method = var.authentication_method
  aws_account_id        = var.aws_account_id
  edition               = var.quicksight_edition
  notification_email    = var.quicksight_notification_email

  lifecycle {
    ignore_changes = [edition]
  }
}

# ----------------------------------------------------------------------------
# QuickSight Groups
# ----------------------------------------------------------------------------

resource "aws_quicksight_group" "authors" {
  aws_account_id = var.aws_account_id
  namespace      = var.quicksight_namespace
  group_name     = local.authors_group_name
  description    = "Author group for ${var.resource_prefix} dashboards"
}

resource "aws_quicksight_group" "readers" {
  aws_account_id = var.aws_account_id
  namespace      = var.quicksight_namespace
  group_name     = local.readers_group_name
  description    = "Reader group for ${var.resource_prefix} dashboards"
}

# ----------------------------------------------------------------------------
# Optional QuickSight Admin/Author User
# ----------------------------------------------------------------------------

resource "aws_quicksight_user" "admin" {
  count = var.provision_admin_user ? 1 : 0

  aws_account_id = var.aws_account_id
  email          = var.quicksight_admin_email
  identity_type  = var.quicksight_identity_type
  namespace      = var.quicksight_namespace
  user_name      = var.quicksight_admin_user_name
  user_role      = var.quicksight_admin_user_role
}

resource "aws_quicksight_group_membership" "admin_authors" {
  count = var.provision_admin_user ? 1 : 0

  aws_account_id = var.aws_account_id
  group_name     = aws_quicksight_group.authors.group_name
  member_name    = aws_quicksight_user.admin[0].user_name
  namespace      = var.quicksight_namespace
}

# ----------------------------------------------------------------------------
# QuickSight Data Source - Athena
# ----------------------------------------------------------------------------

resource "aws_quicksight_data_source" "athena" {
  aws_account_id = var.aws_account_id
  data_source_id = local.data_source_id
  name           = local.data_source_name
  type           = "ATHENA"

  parameters {
    athena {
      work_group = var.athena_workgroup_name
    }
  }

  permission {
    principal = aws_quicksight_group.authors.arn
    actions = [
      "quicksight:DescribeDataSource",
      "quicksight:DescribeDataSourcePermissions",
      "quicksight:PassDataSource",
      "quicksight:UpdateDataSource",
      "quicksight:DeleteDataSource",
      "quicksight:UpdateDataSourcePermissions"
    ]
  }

  permission {
    principal = aws_quicksight_group.readers.arn
    actions = [
      "quicksight:DescribeDataSource",
      "quicksight:DescribeDataSourcePermissions",
      "quicksight:PassDataSource"
    ]
  }

  ssl_properties {
    disable_ssl = false
  }

  tags = var.tags

  depends_on = [
    aws_quicksight_group.authors,
    aws_quicksight_group.readers,
    aws_quicksight_account_subscription.this
  ]
}


