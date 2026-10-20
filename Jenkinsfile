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
        EC2_HOST = '15.206.68.113'
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
                        if errorlevel 1 exit /b 1
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
                        if errorlevel 1 (
                            docker logout
                            exit /b 1
                        )

                        docker push %DOCKERHUB_NAMESPACE%/todo-summary-frontend:%IMAGE_TAG%
                        if errorlevel 1 (
                            docker logout
                            exit /b 1
                        )

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
                        setlocal

                        echo ===== FIX SSH KEY PERMISSIONS =====
                        for /f "delims=" %%I in ('whoami') do set "JENKINS_ACCOUNT=%%I"

                        icacls "%SSH_KEY%" /inheritance:r
                        if errorlevel 1 exit /b 1

                        icacls "%SSH_KEY%" /remove:g *S-1-5-32-545
                        icacls "%SSH_KEY%" /grant:r "%JENKINS_ACCOUNT%:(R)"
                        if errorlevel 1 exit /b 1

                        echo ===== DEPLOY AND VERIFY =====
                        ssh -i "%SSH_KEY%" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL %SSH_USER%@%EC2_HOST% "bash -s -- '%IMAGE_TAG%' '%DOCKERHUB_NAMESPACE%'" < "%WORKSPACE%\\deploy-remote.sh"

                        if errorlevel 1 (
                            echo Deployment or rollback failed. Review Console Output.
                            exit /b 1
                        )
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
            echo 'Pipeline failed. Review Console Output, including rollback status.'
        }
        always {
            echo 'Pipeline execution finished.'
        }
    }
}
