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
                    script {
                        checkout scm: [
                            $class: 'GitSCM',
                            userRemoteConfigs: [[url: 'https://github.com/tbalza/kubernetes-cicd.git']],
                            branches: [[name: '*/main']]
                        ]
                    }
                    script {
                        COMMIT_ID = sh(
                            script: "git log -n 1 --pretty=format:'%H'",
                            returnStdout: true
                        ).trim()
                    }
                }
            }
        }
        stage('Build and Push Image') {
            steps {
                container('kaniko') { // pending argocd image updater. ${ECR_REPO}:${COMMIT_ID}
                    script { // ${ECR_REPO} defined in secrets.yaml using ESO, and loaded as env var in agent pod via `secretEnvVars` in values.yaml
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