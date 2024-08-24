pipeline {
    agent {
        kubernetes {
            inheritFrom 'default'
        }
    }
    environment {
        SKIP_ALL = 'false' // Initialize the flag as false (for argocd-image-updater check)
    }
    triggers {
        // Poll SCM every 5 minutes
        //pollSCM('H/5 * * * *')
        githubPush() // this sets up the pipeline to receive a GitHub webhook
    }
    stages {
        stage('Checkout Code') {
            steps {
                container('jnlp') {
                    checkout scm: [
                        $class: 'GitSCM',
                        branches: [[name: '*/main']],
                        userRemoteConfigs: [[url: "${REPO_URL}"]] // this lets jenkins/github-plugin know the webhook ping is related to the repo
                    ]
                    script {  // correct usage of script block to handle Groovy scripting
                        env.GIT_COMMIT = sh(script: "git rev-parse HEAD", returnStdout: true).trim()
                        echo "Current GIT COMMIT: ${env.GIT_COMMIT}"

                        // retrieve the last committer's name
                        env.GIT_AUTHOR_NAME = sh(script: "git --no-pager show -s --format='%an' ${env.GIT_COMMIT}", returnStdout: true).trim()
                        echo "Last commit made by: ${env.GIT_AUTHOR_NAME}"

                        // Check if the author is 'argocd-image-updater'
                        if (env.GIT_AUTHOR_NAME == 'argocd-image-updater') {
                            echo "Commit made by ArgoCD Image Updater. Marking build as successful and skipping remaining stages."
                            env.SKIP_ALL = 'true'
                            currentBuild.result = 'SUCCESS' // Set build result to SUCCESS
                        }
                    }
                }
            }
        }
        stage('Check ECR for Latest Image Commit') {
            when {
                expression { env.SKIP_ALL == 'false' }
            }
            steps {
                container('jnlp') {
                    script {
                        def images = ecrListImages(repositoryName: "${ECR_REPO_NAME}")
                        def tagList = []

                        if (images) {
                            echo "Images Object: ${images}"
                            images.each { item ->
                                if (item && item.imageTag) {
                                    echo "Found Tag: ${item.imageTag}"
                                    tagList << item.imageTag
                                }
                            }
                        } else {
                            echo "Images Object is null or unavailable"
                        }

                        if (tagList.isEmpty()) {
                            echo "No tagged images found in ECR. Proceeding with build."
                            env.LATEST_ECR_COMMIT = ''
                            env.BUILD_NEEDED = 'true'
                        } else {
                            tagList.each {
                                echo "Extracted Image Tag: $it"
                            }
                            env.LATEST_ECR_COMMIT = tagList.last()
                            echo "Latest ECR Image Commit ID: ${env.LATEST_ECR_COMMIT}"
                        }
                    }
                }
            }
        }
        stage('Check for Django Changes') {
            when {
                expression { env.SKIP_ALL == 'false' }
            }
            steps {
                container('jnlp') {
                    script {
                        if (env.LATEST_ECR_COMMIT) {
                            def changes = sh(script: "git diff --name-only ${env.LATEST_ECR_COMMIT} ${env.GIT_COMMIT} | grep '^django-todo/' || true", returnStdout: true).trim()
                            echo "Git diff completed between ${env.LATEST_ECR_COMMIT} and ${env.GIT_COMMIT}."
                            if (changes.isEmpty()) {
                                echo "No changes in the Django directory since the last ECR image commit. No build needed."
                                env.BUILD_NEEDED = 'false' // Explicitly marking no build needed
                            } else {
                                echo "Changes detected in Django. Proceeding with build."
                                env.BUILD_NEEDED = 'true'
                            }
                        } else {
                            echo "No valid ECR image commit found or no image tags available. Proceeding with build as fallback."
                            env.BUILD_NEEDED = 'true'
                        }
                    }
                }
            }
        }
        stage('Build and Push Image') {
            when {
                expression { env.BUILD_NEEDED == 'true' && env.SKIP_ALL == 'false' }
            }
            steps {
                container('kaniko') {
                    sh """
                    /kaniko/executor --dockerfile /home/jenkins/agent/workspace/build-django/django-todo/Dockerfile \
                                      --context /home/jenkins/agent/workspace/build-django/django-todo/ \
                                      --destination ${ECR_REPO}:${env.GIT_COMMIT} \
                                      --cache=true
                    """
                }
            }
        }
    }
    post {
        always {
            echo "Build completed successfully."
        }
    }
}
