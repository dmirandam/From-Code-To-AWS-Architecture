#--------------CodePipeline-----------------

resource "aws_iam_role" "codepipeline-role" {
  name = "codepipeline-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
      },
    ]
  })
}


data "aws_iam_policy_document" "tf-cicd-policies-cp" {
  statement {
    sid = ""
    actions = ["codestar-connections:UseConnection"]
    resources = ["*"]
    effect = "Allow"
  }

  statement {
    sid = ""
    actions = ["cloudwatch:*", "s3:*", "codebuild:*"]
    resources = ["*"]
    effect = "Allow"
  }  
}

resource "aws_iam_policy" "tf-pipeline-policy" {
  name = "tf-pipeline-policy"
  path = "/"
  policy = data.aws_iam_policy_document.tf-cicd-policies-cp.json 
}

resource "aws_iam_role_policy_attachment" "tf-pipeline-attachment" {
  role = aws_iam_role.codepipeline-role.id
  policy_arn = aws_iam_policy.tf-pipeline-policy.arn
}


#--------------Codebuild-----------------

resource "aws_iam_role" "codebuild-role" {
  name = "codebuild-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      },
    ]
  })
}

data "aws_iam_policy_document" "tf-cicd-policies-cb" {
  statement {
    sid = ""
    actions = ["logs:*","s3:*","codebuild:*", "secretmanager:*", "iam:*"]
    resources = ["*"]
    effect = "Allow"
  }
}

resource "aws_iam_policy" "tf-build-policy" {
  name = "tf-build-policy"
  path = "/"
  policy = data.aws_iam_policy_document.tf-cicd-policies-cb.json 
}

resource "aws_iam_role_policy_attachment" "tf-build-attachment-1" {
  role = aws_iam_role.codebuild-role.id
  policy_arn = aws_iam_policy.tf-build-policy.arn
}

resource "aws_iam_role_policy_attachment" "tf-build-attachment-2" {
  role = aws_iam_role.codebuild-role.id
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

#-------------------------s3--------------------------------
resource "aws_s3_bucket" "codepipeline_artifacts" {
  bucket = "c0d3pipeline-artfacts-B"
}
#------------------------pipe--------------------------------


resource "aws_codebuild_project" "tf-plan" {
  name          = "tf-cicd-plan"
  description   = "test_codebuild_project"
  build_timeout = "5"
  service_role  = aws_iam_role.codebuild-role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "hashicorp/terraform:latest"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "SERVICE_ROLE" 
    registry_credential {
        credential = var.dockerhub_credentials
        credential_provider = "SECRETS_MANAGER"
    }
  }
  source {
    type = "CODEPIPELINE"
    buildspec = file("buildspec/plan-buildspec.yml")
  }
}


resource "aws_codebuild_project" "tf-apply" {
  name          = "tf-cicd-apply"
  description   = "test_codebuild_project_apply"
  build_timeout = "5"
  service_role  = aws_iam_role.codebuild-role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "hashicorp/terraform:latest"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "SERVICE_ROLE" 
    registry_credential {
        credential = var.dockerhub_credentials
        credential_provider = "SECRETS_MANAGER"
    }
  }
  source {
    type = "CODEPIPELINE"
    buildspec = file("buildspec/apply-buildspec.yml")
  }
}

resource "aws_codepipeline" "cicd-pipeline" {
    name     = "cicd-pipeline-back"
    role_arn = aws_iam_role.codepipeline-role.arn

    artifact_store {
        location = aws_s3_bucket.codepipeline_artifacts.id
        type     = "S3"
    }  

    stage {
        name = "Source"
        action {
            name             = "Source"
            category         = "Source"
            owner            = "AWS"
            provider         = "CodeStarSourceConnection"
            version          = "1"
            output_artifacts = ["tf-code"]
            configuration = {
                FullRepositoryId = "AgrimarketUN/AWS-Terraform-Pipeline-Back"
                BranchName = "main"
                ConnectionArn = var.codestar_credentials
                OutputArtifactFormat = "CODE_ZIP"

            }
        }
    }

    stage {
      name = "Plan"
      action {
        name            = "Build"
        category        = "Build"
        provider        = "CodeBuild"
        version         = "1" 
        owner           = "AWS"
        input_artifacts = ["tf-code"]
        configuration = {
            ProjectName = "tf-cicd-plan"
            
        }
      }
    }

    stage {
      name = "Deploy"
      action {
        name            = "Deploy"
        category        = "Build"
        provider        = "CodeBuild"
        version         = "1" 
        owner           = "AWS"
        input_artifacts = ["tf-code"]
        configuration = {
            ProjectName = "tf-cicd-apply"
            
        }
      }
    }
}





