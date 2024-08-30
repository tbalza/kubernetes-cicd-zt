pipeline {
    agent {
        kubernetes {
            inheritFrom 'default'
        }
    }
    triggers {
        // Poll SCM every 5 minutes
        //pollSCM('H/5 * * * *')
        githubPush() // this sets up the pipeline to receive a GitHub webhook
    }
    stages {
        stage('Setup Environment') {
            steps {
                script {
                    // Reset SKIP_ALL to false at the start to handle any residual state issues
                    env.SKIP_ALL = 'false'
                }
            }
        }
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
                        echo "SKIP_ALL after checkout: ${env.SKIP_ALL}"
                    }
                }
            }
        }
        stage('Check ECR for Latest Image Commit') {
            steps {
                container('jnlp') {
                    script {
                        echo "SKIP_ALL before checking ECR: ${env.SKIP_ALL}"
                        if (env.SKIP_ALL == 'false') {
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
                        } else {
                            echo "Skipping ECR check as SKIP_ALL is set to true."
                        }
                    }
                }
            }
        }
        stage('Check for Django Changes') {
            steps {
                container('jnlp') {
                    script {
                        echo "SKIP_ALL before checking Django Changes: ${env.SKIP_ALL}"
                        if (env.SKIP_ALL == 'false') {
                            if (env.LATEST_ECR_COMMIT) {
                                def changes = sh(script: "git diff --name-only ${env.LATEST_ECR_COMMIT} ${env.GIT_COMMIT} | grep '^django-todo/' || true", returnStdout: true).trim()
                                echo "Git diff completed between ${env.LATEST_ECR_COMMIT} and ${env.GIT_COMMIT}."
                                if (changes.isEmpty()) {
                                    echo "No changes in the Django directory since the last ECR image commit. No build needed."
                                    env.BUILD_NEEDED = 'false'
                                } else {
                                    echo "Changes detected in Django. Proceeding with build."
                                    env.BUILD_NEEDED = 'true'
                                }
                            } else {
                                echo "No valid ECR image commit found or no image tags available. Proceeding with build as fallback."
                                env.BUILD_NEEDED = 'true'
                            }
                        } else {
                            echo "Skipping Django changes check as SKIP_ALL is set to true."
                        }
                    }
                }
            }
        }
        stage('SonarQube Analysis') {
            steps {
                container('jnlp') {
                    script {
                        if (env.BUILD_NEEDED == 'true' && env.SKIP_ALL == 'false') {
                            scannerHome = tool 'SonarQubeScanner'
                            echo "Attempting to revoke the existing SonarQube token..."
                            sh(script: """
                            curl -X POST -H "Content-Type: application/x-www-form-urlencoded" \
                                -d "name=token" \
                                -u admin:${SONARQUBE_PASSWORD} \
                                http://sonarqube-sonarqube.sonarqube.svc.cluster.local:9000/api/user_tokens/revoke
                            """, returnStdout: true).trim()

                            sleep 5
                            echo "Generating a new SonarQube token..."
                            def response = sh(script: """
                            curl -X POST -H "Content-Type: application/x-www-form-urlencoded" \
                                -d "name=token" \
                                -u admin:${SONARQUBE_PASSWORD} \
                                http://sonarqube-sonarqube.sonarqube.svc.cluster.local:9000/api/user_tokens/generate
                            """, returnStdout: true).trim()

                            sleep 5
                            def jsonResponse = readJSON text: response
                            env.SQ_TOKEN = jsonResponse.token
                            echo "New SonarQube token stored"

                            withSonarQubeEnv('SonarQube') {
                                sh """
                                ${scannerHome}/bin/sonar-scanner \
                                    -Dsonar.projectKey=django_todo_project \
                                    -Dsonar.sources=/home/jenkins/agent/workspace/build-django/django-todo/ \
                                    -Dsonar.host.url=http://sonarqube-sonarqube.sonarqube.svc.cluster.local:9000 \
                                    -Dsonar.token=${env.SQ_TOKEN}
                                """
                            }
                        } else {
                            echo "Skipping SonarQube analysis as conditions are not met."
                        }
                    }
                }
            }
        }
        stage('Build and Push Image') {
            steps {
                container('kaniko') {
                    script {
                        if (env.BUILD_NEEDED == 'true' && env.SKIP_ALL == 'false') {
                            sh """
                            /kaniko/executor --dockerfile /home/jenkins/agent/workspace/build-django/django-todo/Dockerfile \
                                              --context /home/jenkins/agent/workspace/build-django/django-todo/ \
                                              --destination ${ECR_REPO}:${env.GIT_COMMIT} \
                                              --cache=true
                            """
                        } else {
                            echo "Skipping image build and push as conditions are not met."
                        }
                    }
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
