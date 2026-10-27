terraform {
  required_version = ">= 1.10"

  required_providers {
    pagerduty = {
      source  = "PagerDuty/pagerduty"
      version = "~> 3.37"
    }
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.60"
    }
  }
}
