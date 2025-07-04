pipeline {
    agent any

    environment {
        // --- Configuration ---
        // These should be configured in Jenkins UI > Manage Jenkins > Configure System
        // Or fetched from a secure source.
        GCP_PROJECT_ID      = 'it-devops-tf'
        GCP_REGION          = 'asia-south2'
        APP_NAME            = 'two-tier-app'
        // The full URL to the Docker image repository in Artifact Registry
        AR_DOCKER_REPO      = "asia-south2-docker.pkg.dev/it-devops-tf/app-images"
        // The full URL to the Helm chart repository in Artifact Registry
        AR_HELM_REPO        = "oci://asia-south2-docker.pkg.dev/it-devops-tf/helm-charts"
        // Path to the Helm chart within the Git repository
        HELM_CHART_PATH     = "helm/two-tier-app"
    }

    stages {
        stage('Checkout Code') {
            steps {
                echo 'Checking out code from GitHub...'
                checkout scm
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    // Use the short Git commit hash as the image tag for traceability
                    def shortCommit = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
                    env.IMAGE_TAG = shortCommit
                    env.DOCKER_IMAGE_NAME = "${env.AR_DOCKER_REPO}/${env.APP_NAME}:${env.IMAGE_TAG}"

                    echo "Building Docker image: ${env.DOCKER_IMAGE_NAME}"
                    // The 'gcloud' command configures Docker to authenticate with Artifact Registry
                    // This works because the Jenkins VM has the necessary IAM SA attached.
                    sh 'gcloud auth configure-docker ${GCP_REGION}-docker.pkg.dev --quiet'
                    sh "docker build -t ${env.DOCKER_IMAGE_NAME} ."
                }
            }
        }

        stage('Push Docker Image to Artifact Registry') {
            steps {
                echo "Pushing Docker image: ${env.DOCKER_IMAGE_NAME}"
                sh "docker push ${env.DOCKER_IMAGE_NAME}"
            }
        }

        stage('Package and Push Helm Chart') {
            steps {
                script {
                    // Update the image tag in the Helm chart's values.yaml
                    echo "Updating Helm chart with image tag: ${env.IMAGE_TAG}"
                    sh "sed -i 's/tag: .*/tag: ${env.IMAGE_TAG}/' ${env.HELM_CHART_PATH}/values.yaml"

                    // Get the chart version from Chart.yaml
                    def chartVersion = sh(returnStdout: true, script: "grep 'version:' ${env.HELM_CHART_PATH}/Chart.yaml | awk '{print \$2}'").trim()
                    echo "Packaging Helm chart version: ${chartVersion}"
                    
                    // Authenticate Helm with Artifact Registry
                    sh 'gcloud auth print-access-token | helm registry login -u oauth2accesstoken --password-stdin https://${GCP_REGION}-docker.pkg.dev'

                    // Package and push the Helm chart
                    sh "helm package ${env.HELM_CHART_PATH}"
                    def chartPackageName = "${env.APP_NAME}-${chartVersion}.tgz"
                    echo "Pushing Helm chart package: ${chartPackageName} to ${env.AR_HELM_REPO}"
                    sh "helm push ${chartPackageName} ${env.AR_HELM_REPO}"
                }
            }
        }
    }

    post {
        always {
            echo 'Pipeline finished.'
            // Clean up workspace to save disk space on Jenkins master
            cleanWs()
        }
    }
}