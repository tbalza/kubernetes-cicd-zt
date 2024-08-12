pipeline {
    agent {
        kubernetes {
            inheritFrom 'default' // `default` created in upstream helm chart by default, Kaniko container config added to default via `additionalContainers` in values.yaml
        }
    }
    stages {
        stage('Checkout Code') {
            steps {
                container('jnlp') {
                    // Checkout code
                    git branch: 'main', url: "${REPO_URL}"
                }
            }
        }
        stage('Initialize') {
            steps {
                container('jnlp') {
                    script {
                        // Capture the current Git commit ID after checkout
                        env.GIT_COMMIT = sh(script: "git rev-parse HEAD", returnStdout: true).trim()
                    }
                }
            }
        }
        stage('Check ECR for Latest Image Commit') {
            steps {
                container('jnlp') {
                    script {
                        // Fetch the most recent image tag from ECR, which should be a commit ID
                        env.LATEST_ECR_COMMIT = sh(
                            script: "aws ecr describe-images --repository-name ${ECR_REPO_NAME} --region ${REGION} --query 'sort_by(imageDetails, &imagePushedAt)[-1].imageTags[0]' --output text || echo ''",
                            returnStdout: true
                        ).trim()
                    }
                    echo env.LATEST_ECR_COMMIT ? "Latest ECR Image Commit ID: ${LATEST_ECR_COMMIT}" : "No images found in ECR. Proceeding with build."
                    script {
                        if (env.LATEST_ECR_COMMIT == '') {
                            env.BUILD_NEEDED = 'true' // If no images found in ECR, build
                        }
                    }
                }
            }
        }
        stage('Check for Django Changes') {
            steps {
                container('jnlp') {
                    script {
                        if (env.LATEST_ECR_COMMIT) {
                            def changesInDjango = sh(
                                script: "git diff --name-only ${LATEST_ECR_COMMIT} ${GIT_COMMIT} | grep '^django/'",
                                returnStdout: true
                            ).trim()
                            if (changesInDjango.isEmpty()) {
                                echo "No changes in the Django directory since last ECR image commit. Skipping build."
                                currentBuild.result = 'NOT_BUILT'
                            } else {
                                echo "Changes detected in Django. Proceeding with build."
                                env.BUILD_NEEDED = 'true'
                            }
                        }
                    }
                }
            }
        }
        stage('Build and Push Image') {
            when {
                expression {
                    return env.BUILD_NEEDED == 'true'
                }
            }
            steps {
                container('kaniko') {
                    sh """
                    /kaniko/executor --dockerfile /home/jenkins/agent/workspace/build-django/django/Dockerfile \
                                      --context /home/jenkins/agent/workspace/build-django/django/ \
                                      --destination ${ECR_REPO}:${GIT_COMMIT} \
                                      --cache=true
                    """
                }
            }
        }
    }
    post {
        always {
            echo "Cleaning up post build"
        }
    }
}