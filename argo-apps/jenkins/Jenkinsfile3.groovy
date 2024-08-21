pipeline {
    agent {
        kubernetes {
            inheritFrom 'default'
        }
    }
    stages {
        stage('Checkout and Verify Commit') {
            steps {
                container('jnlp') {
                    script {
                        // Checking out the code and identifying the committer
                        checkout scm: [
                            $class: 'GitSCM',
                            userRemoteConfigs: [[url: 'https://github.com/tbalza/kubernetes-cicd.git']],
                            branches: [[name: '*/main']]
                        ]
                        // Get the last commit's author
                        def commitAuthor = sh(
                            script: "git log -1 --pretty=format:'%an'",
                            returnStdout: true
                        ).trim()
                        // Check if the commit was made by argocd-image-updater and abort if true
                        if (commitAuthor == 'argocd-image-updater') {
                            echo "Commit by ArgoCD Image Updater, skipping build"
                            currentBuild.result = 'ABORTED'
                            return
                        }
                    }
                }
            }
        }
        stage('Build and Push Image') {
            when {
                expression {
                    // Only proceed if the build was not aborted
                    return currentBuild.result != 'ABORTED'
                }
            }
            steps {
                container('kaniko') {
                    script {
                        // Building and pushing the Docker image
                        sh """
                        /kaniko/executor --dockerfile /home/jenkins/agent/workspace/build-django/django/Dockerfile \
                                          --context /home/jenkins/agent/workspace/build-django/django/ \
                                          --destination ${ECR_REPO}:${COMMIT_ID} \
                                          --cache=true
                        """
                    }
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
