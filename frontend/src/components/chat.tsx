import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { EllipsisVertical, Trash2 } from "lucide-react";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
  DialogFooter,
  DialogClose,
} from "@/components/ui/dialog"

const Chat: React.FC<{ username: string }> = ({ username }) => {





  return (
    <div className="w-full h-screen flex flex-col">
      {/* Шапка */}
      <div className="w-full h-16 bg-white/10 rounded-t-xl flex items-center px-4">
        {/* Левая часть: аватар + ник */}
        <div className="flex items-center gap-2">
          <Avatar className="w-10 h-10">
            <AvatarImage
              src="https://i.pinimg.com/1200x/5f/e2/d8/5fe2d8baea7ce4065407b899aeb16b74.jpg"
              className="rounded-full"
            />
            <AvatarFallback>{username[0]}</AvatarFallback>
          </Avatar>
          <h1 className="text-neutral-950 text-2xl font-semibold">{username}</h1>
        </div>

        {/* Правая часть: меню */}
        <div className="ml-auto">
            <Popover>
                <Tooltip>
                    <TooltipTrigger>
                        <PopoverTrigger asChild>
                            <Button
                                variant="outline"
                                size="icon"
                                className="cursor-pointer bg-white/20 hover:bg-white/10 border-none"
                            >
                                <EllipsisVertical className="text-white" />
                            </Button>
                        </PopoverTrigger>
                    </TooltipTrigger>
                    <TooltipContent>
                        <p>Показать меню</p>
                    </TooltipContent>
                </Tooltip>
                <PopoverContent
                    className="w-40 bg-white/20 rounded-xl border-none"
                    side="bottom"
                    align="end"
                    sideOffset={5}
                    alignOffset={-5}
                >
                    <div>
                        <Dialog>
                            <DialogTrigger asChild>
                                <Button
                                    variant="destructive"
                                    size="default"
                                    className="cursor-pointer  border-none"
                                    onClick={() => {}}
                                >
                                    <Trash2 className="text-white" /> Удалить чат
                                </Button>
                            </DialogTrigger>
                            <DialogContent className="sm:max-w-md bg-white/50 rounded-xl border-none">
                                <DialogHeader>
                                    <DialogTitle>Удалить чат</DialogTitle>
                                    <DialogDescription className="text-white">
                                        Вы уверены, что хотите удалить чат?
                                    </DialogDescription>
                                </DialogHeader>
                                <DialogFooter className="sm:justify-start">
                                    <DialogClose asChild>
                                        <Button type="button" variant="secondary" className="cursor-pointer">
                                        Отмена
                                        </Button>
                                    </DialogClose>
                                    <DialogClose asChild>
                                        <Button type="button" variant="destructive" className="cursor-pointer">
                                        Удалить
                                        </Button>
                                    </DialogClose>
                                </DialogFooter>
                            </DialogContent>
                        </Dialog>
                    </div>
                </PopoverContent>
            </Popover>
        </div>
      </div>

      {/* Основной блок чата */}
      <div className="w-full flex-1 p-4 overflow-y-auto">
        {/* Здесь будут сообщения чата */}
        
      </div>
    </div>
  );
};

export default Chat;
