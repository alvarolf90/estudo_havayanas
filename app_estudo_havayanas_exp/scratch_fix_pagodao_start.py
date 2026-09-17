import io

path = "/sessions/rcw-019lzxms5ajbcg9v1k2gehws/mnt/Aplicativos_Shiny/projeto_havayanas/app_estudo_havayanas_exp/app.R"
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

old = '''        if (estado$fase_atual == "Levada") {
          estado$padrao_atual <- sample(input$levadas_ativas, 1)
          opcoes_rep <- seq(input$rep_levadas[1], input$rep_levadas[2], by = 2)
          estado$compassos_restantes <- if(length(opcoes_rep) == 1) opcoes_rep else sample(opcoes_rep, 1)
        } else {
          estado$padrao_atual <- sample(input$conv_ativas, 1)
          estado$compassos_restantes <- get_duracao(estado$padrao_atual, df_convencoes)
        }
      }
      estado$compassos_tocados <- 0
      preencher_proximo()'''

assert content.count(old) == 1, f"found {content.count(old)} occurrences"

new = '''        if (estado$fase_atual == "Levada") {
          estado$padrao_atual <- sample(input$levadas_ativas, 1)
          opcoes_rep <- seq(input$rep_levadas[1], input$rep_levadas[2], by = 2)
          estado$compassos_restantes <- if(length(opcoes_rep) == 1) opcoes_rep else sample(opcoes_rep, 1)
        } else {
          estado$padrao_atual <- sample(input$conv_ativas, 1)
          estado$compassos_restantes <- get_duracao(estado$padrao_atual, df_convencoes)
        }
        
        if (estado$fase_atual == "Levada" && tolower(estado$padrao_atual) == "pagodão") {
          estado$proxima_fase <- "Levada"
          estado$proximo_padrao <- estado$padrao_atual
          estado$proximos_compassos <- estado$compassos_restantes
          estado$fase_atual <- "Convenção"
          estado$padrao_atual <- "Pausa"
          estado$compassos_restantes <- 1
        }
      }
      estado$compassos_tocados <- 0
      preencher_proximo()'''

content = content.replace(old, new)

with io.open(path, "w", encoding="utf-8") as f:
    f.write(content)

print("done")
