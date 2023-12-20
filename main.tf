terraform {
  required_providers {
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "4.13.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "4.13.0"
    }
  }
  backend "gcs" {
    bucket = "nais-ppa-state"
  }
}

resource "google_project" "project" {
  name            = "nais-ppa"
  project_id      = "nais-ppa"
  folder_id       = "201134087427"
  billing_account = "014686-D32BB4-68DF8E"
}

resource "google_project_service" "services" {
  for_each = toset([
    "artifactregistry.googleapis.com",
    "cloudbilling.googleapis.com",
    "iamcredentials.googleapis.com",
  ])

  project                    = google_project.project.project_id
  service                    = each.value
  disable_dependent_services = true
}

# Setup workload identity in this project
resource "google_iam_workload_identity_pool" "pool" {
  project  = google_project.project.project_id
  provider = google-beta

  display_name              = "nais identity pool"
  workload_identity_pool_id = "nais-identity-pool"
}

resource "google_iam_workload_identity_pool_provider" "provider" {
  project  = google_project.project.project_id
  provider = google-beta

  display_name                       = "Github OIDC provider"
  workload_identity_pool_id          = google_iam_workload_identity_pool.pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc-provider"
  attribute_mapping = {
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.aud"              = "assertion.aud"
    "attribute.actor"            = "assertion.actor"
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
  }
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Setup repository
resource "google_artifact_registry_repository" "nais_ppa" {
  project  = google_project.project.project_id
  provider = google-beta

  location      = "europe-north1"
  repository_id = "zoom"
  description   = "zoom.us deb, updated daily"
  format        = "apt"
}

resource "google_artifact_registry_repository_iam_member" "public-readable" {
  project  = google_project.project.project_id
  provider = google-beta

  location   = google_artifact_registry_repository.nais_ppa.location
  repository = google_artifact_registry_repository.nais_ppa.name
  role       = "roles/artifactregistry.reader"
  member     = "allUsers"
}

# Setup Zoom deb uploaer
resource "google_service_account" "zoom-repo-update-deb-uploader" {
  project = google_project.project.project_id

  account_id   = "zoom-repo-update-deb-uploader"
  display_name = "zoom-repo-update deb uploader"
}

resource "google_artifact_registry_repository_iam_member" "zoom-github-actions-deb-uploader" {
  project  = google_project.project.project_id
  provider = google-beta

  location   = google_artifact_registry_repository.nais_ppa.location
  repository = google_artifact_registry_repository.nais_ppa.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.zoom-repo-update-deb-uploader.email}"
}

resource "google_service_account_iam_member" "zoom-repo-update-workload-identity" {
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.pool.name}/attribute.repository/nais/zoombuster3000"
  role               = "roles/iam.workloadIdentityUser"
  service_account_id = google_service_account.zoom-repo-update-deb-uploader.id
}
