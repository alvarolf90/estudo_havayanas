# Publica no Posit Connect Cloud a versao do app que esta no ultimo commit (HEAD),
# a mesma que esta no GitHub Pages - mudancas locais ainda nao commitadas ficam de fora.
# Rodar do Terminal do RStudio, na raiz do repo:  Rscript _deploy_connect/deploy_connect.R
raiz <- normalizePath(".")
tmp <- file.path(tempdir(), "hv_cc")
unlink(tmp, recursive = TRUE); dir.create(tmp)
system2("sh", c("-c", shQuote(sprintf("git archive HEAD app_estudo_havayanas_exp | tar -x -C %s", shQuote(tmp)))))
app_dir <- file.path(tmp, "app_estudo_havayanas_exp")
arqs <- list.files(app_dir, recursive = TRUE, all.files = FALSE)
arqs <- arqs[!grepl("\\.(py|DS_Store|xlsx)$", arqs) & !grepl("^rsconnect/", arqs)]
cat("Arquivos:", length(arqs), "\n")
sink(file.path(raiz, "_deploy_connect", "deploy_out.txt"), split = TRUE)
library(rsconnect)
r <- try(deployApp(appDir = app_dir, appFiles = arqs, appName = "estudo_havayanas",
                   appTitle = "Estudo Havayanas", recordDir = file.path(raiz, "_deploy_connect"),
                   account = "alvaroledoferreira", server = "connect.posit.cloud",
                   launch.browser = FALSE, forceUpdate = TRUE, lint = FALSE))
print(r)
cat("DEPLOY_FIM\n")
sink()
