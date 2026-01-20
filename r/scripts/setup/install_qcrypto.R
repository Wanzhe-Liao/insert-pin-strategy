options(download.file.method = "wininet")
if (nzchar(Sys.getenv("http_proxy"))) Sys.setenv(http_proxy = Sys.getenv("http_proxy"))
if (nzchar(Sys.getenv("https_proxy"))) Sys.setenv(https_proxy = Sys.getenv("https_proxy"))
library("devtools")
token <- Sys.getenv("GITHUB_TOKEN")
if (!nzchar(token)) token <- Sys.getenv("GITHUB_PAT")
if (nzchar(token)) {
  devtools::install_github("HaobinZhou/QCrypto", auth_token = token)
} else {
  devtools::install_github("HaobinZhou/QCrypto")
}
