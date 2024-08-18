// Uses Declarative syntax to run commands inside a container.
def COMMIT_ID=''

pipeline {
    agent {
        label 'jenkins-jenkins-agent'
    }
    stages {
        stage('Git clone') {
            steps {
                container('jnlp') {
                    git 'https://github.com/rafimojabi/simpleGoApp.git'
                }
                script {
                    COMMIT_ID = sh(
                        script: "git log -n 1 --pretty=format:'%H'",
                        returnStdout: true
                    ).trim()
                }
            }
        }
        stage('Kaniko Build Image') {
            steps {
                container('kaniko') {
                    sh "echo $REGISTRY_CRED > /kaniko/.docker/config.json"
                    sh "/kaniko/executor --context `pwd` --destination rafimojabi/tools:$COMMIT_ID"
                }
            }
        }
    }
}