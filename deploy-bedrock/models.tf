data "aws_bedrock_foundation_model_agreement_offers" "this" {
  for_each = local.models_with_agreement

  model_id   = each.value.model_id
  offer_type = "PUBLIC"
}

resource "aws_bedrock_foundation_model_agreement" "this" {
  for_each = local.models_with_agreement

  model_id    = data.aws_bedrock_foundation_model_agreement_offers.this[each.key].model_id
  offer_token = data.aws_bedrock_foundation_model_agreement_offers.this[each.key].offers[0].offer_token

  lifecycle {
    ignore_changes = [offer_token]
  }
}

resource "aws_bedrock_use_case_for_model_access" "anthropic" {
  count = var.enable_anthropic_use_case ? 1 : 0

  form_data = jsonencode(var.anthropic_use_case_form)
}
