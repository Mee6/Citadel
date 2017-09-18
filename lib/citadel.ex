defmodule Citadel do
  def init do
    Citadel.Backbone.init()
  end

  def start do
    :mnesia.start()
    init()
  end
end
