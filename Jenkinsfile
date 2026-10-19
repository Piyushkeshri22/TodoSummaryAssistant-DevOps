pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        timeout(time: 45, unit: 'MINUTES')
        skipDefaultCheckout(true)
    }

    triggers {
        pollSCM('H/5 * * * *')
    }

    environment {
        DOCKERHUB_NAMESPACE = 'piyushkeshri22'
        EC2_HOST = '13.206.190.227'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Backend Tests') {
            steps {
                dir('Backend/todo-summary-assistant') {
                    bat '''
                        @echo off
                        set "JAVA_HOME=C:\\Program Files\\Eclipse Adoptium\\jdk-17.0.20.101-hotspot"
                        set "PATH=%JAVA_HOME%\\bin;%PATH%"
                        call mvn -B clean test
                    '''
                }
            }
        }

        stage('Frontend Build') {
            steps {
                dir('Frontend/todo') {
                    bat '''
                        @echo off
                        call npm.cmd ci
                        if errorlevel 1 exit /b 1

                        call npm.cmd run build
                        if errorlevel 1 exit /b 1
                    '''
                }
            }
        }

        stage('Build Docker Images') {
            steps {
                script {
                    env.IMAGE_TAG = "build-${env.BUILD_NUMBER}"
                }

                bat '''
                    @echo off
                    docker build --pull -t %DOCKERHUB_NAMESPACE%/todo-summary-backend:%IMAGE_TAG% -f Backend/todo-summary-assistant/Dockerfile Backend/todo-summary-assistant
                    if errorlevel 1 exit /b 1

                    docker build --pull -t %DOCKERHUB_NAMESPACE%/todo-summary-frontend:%IMAGE_TAG% -f Frontend/todo/Dockerfile Frontend/todo
                    if errorlevel 1 exit /b 1
                '''
            }
        }

        stage('Push Images to Docker Hub') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub-creds',
                        usernameVariable: 'DOCKERHUB_USER',
                        passwordVariable: 'DOCKERHUB_TOKEN'
                    )
                ]) {
                    bat '''
                        @echo off
                        powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$env:DOCKERHUB_TOKEN | docker login -u $env:DOCKERHUB_USER --password-stdin"
                        if errorlevel 1 exit /b 1

                        docker push %DOCKERHUB_NAMESPACE%/todo-summary-backend:%IMAGE_TAG%
                        if errorlevel 1 exit /b 1

                        docker push %DOCKERHUB_NAMESPACE%/todo-summary-frontend:%IMAGE_TAG%
                        if errorlevel 1 exit /b 1

                        docker logout
                    '''
                }
            }
        }

        stage('Deploy to EC2') {
            steps {
                withCredentials([
                    sshUserPrivateKey(
                        credentialsId: 'ec2-ssh-key',
                        keyFileVariable: 'SSH_KEY',
                        usernameVariable: 'SSH_USER'
                    )
                ]) {
                    bat '''
                        @echo off

                        ssh -i "%SSH_KEY%" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL %SSH_USER%@%EC2_HOST% "cd ~/todo-app && cp docker-compose.yml docker-compose.yml.previous && sed -i -E 's|image: piyushkeshri22/todo-summary-backend:[^[:space:]]+|image: piyushkeshri22/todo-summary-backend:%IMAGE_TAG%|' docker-compose.yml && sed -i -E 's|image: piyushkeshri22/todo-summary-frontend:[^[:space:]]+|image: piyushkeshri22/todo-summary-frontend:%IMAGE_TAG%|' docker-compose.yml && docker compose pull && docker compose up -d && for i in 1 2 3 4 5 6 7 8 9 10 11 12; do if curl -fsS http://localhost:3000/ > /dev/null && curl -fsS http://localhost:3000/api/todos > /dev/null; then echo 'Deployment healthy'; exit 0; fi; echo 'Waiting for health check'; sleep 5; done; echo 'Health check failed; rolling back'; cp docker-compose.yml.previous docker-compose.yml && docker compose pull && docker compose up -d; exit 1"

                        if errorlevel 1 exit /b 1
                    '''
                }
            }
        }
    }

    post {
        success {
            echo 'CI/CD pipeline completed successfully.'
        }
        failure {
            echo 'Pipeline failed. Review Console Output to identify the failing stage.'
        }
    }
}
