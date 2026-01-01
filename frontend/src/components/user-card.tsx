import React from "react";
import { Card, CardContent, CardTitle } from "@/components/ui/card";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Settings, Search, LogOut } from "lucide-react";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { Badge } from "@/components/ui/badge";

const UserCard: React.FC<{
  username: string;
  avatar: string;
  message?: string;
  me?: boolean;
  isOnline?: boolean;
  unreadCount?: number;
  onClick?: (username: string) => void;
}> = ({ username, avatar, message, me, isOnline = false, unreadCount = 0, onClick }) => {

  return (
    <div className="mb-2">
      {/* делаем Card кликабельным — не используем тег <button> вокруг всего */}
      <Card
        // добавляем cursor-pointer и focus-стили
        className={`${me ? "bg-white/10 border-white/20" : "bg-white/0 border-white/20 hover:bg-white/10"} cursor-pointer focus:outline-none`}
        onClick={me ? () => { } : () => onClick?.(username)}
        role="button"
        tabIndex={0}
      >
        <CardContent>
          <CardTitle>
            <div className="flex items-center gap-2">
                <div className="relative">
                    <Avatar className="w-10 h-10">
                        <AvatarImage src={avatar} />
                        <AvatarFallback>{username[0]}</AvatarFallback>
                    </Avatar>
                    {!me && (
                        <Badge 
                            className={`absolute -top-1 -right-1 h-5 min-w-5 rounded-full p-0 flex items-center justify-center font-mono text-xs border border-fuchsia-500/50
                                ${isOnline ? 'bg-green-500 hover:bg-green-600' : 'bg-gray-500 hover:bg-gray-600'}`}
                            variant="secondary"
                        >
                            {unreadCount > 99 ? '99+' : unreadCount}
                        </Badge>
                    )}
                </div>
                <div className="flex flex-col">
                    <h6 className="text-neutral-950 text-base text-white">{username}</h6>
                    <p className="text-neutral-950 text-xs truncate overflow-hidden text-white">{message}</p>
                </div>

                {me && (
                    <div className="flex gap-2 ml-auto">
                        <Tooltip>
                            <TooltipTrigger>
                                <Button
                                    variant="outline"
                                    size="icon"
                                    className="cursor-pointer bg-white/20 hover:bg-white/10 border-none"
                                    onClick={(e) => {
                                        e.stopPropagation();
                                        console.log("Открыть настройки");
                                    }}
                                >
                                    <Settings />
                                </Button>
                            </TooltipTrigger>
                            <TooltipContent>
                                <p>Настройки</p>
                            </TooltipContent>
                        </Tooltip>

                        <Tooltip>
                            <TooltipTrigger>
                                <Button
                                    variant="outline"
                                    size="icon"
                                    className="cursor-pointer bg-white/20 hover:bg-white/10 border-none"
                                    onClick={(e) => {
                                        e.stopPropagation();
                                        console.log("Поиск");
                                    }}
                                >
                                    <Search />
                                </Button>
                            </TooltipTrigger>
                            <TooltipContent>
                                <p>Поиск новых собеседников</p>
                            </TooltipContent>
                        </Tooltip>

                        <Tooltip>
                            <TooltipTrigger>
                                <Button
                                    variant="outline"
                                    size="icon"
                                    className="cursor-pointer bg-rose-950/50 hover:bg-rose-800/30 border-none"
                                    onClick={(e) => {
                                        e.stopPropagation();
                                        console.log("Выйти");
                                    }}
                                >
                                    <LogOut />
                                </Button>
                            </TooltipTrigger>
                            <TooltipContent>
                                <p>Выйти</p>
                            </TooltipContent>
                        </Tooltip>
                    </div>
                )}
            </div>
          </CardTitle>
        </CardContent>
      </Card>
    </div>
  );
};

export default UserCard;
