import { useState } from "react";
import AnimatedBackground from "../components/animated-background";
import UserCard from "../components/user-card";
import Chat from "../components/chat";

const Home = () => {

    const [username, setUsername] = useState<string | null>(null);

    const avatarUrl = "https://i.pinimg.com/1200x/5f/e2/d8/5fe2d8baea7ce4065407b899aeb16b74.jpg";
    const users = Array.from({ length: 14 }, (_, i) => {
        const index = i + 1;
        return {
            username: `Test${index}`,
            message: `Сообщение от Test${index}`,
            avatar: avatarUrl,
            me: false,
            isOnline: false,
            unreadCount: 124,
        };
    });

    return (
        <AnimatedBackground>
            <div className="w-screen h-screen p-8">
                <div className="w-full h-full bg-black/10 rounded-xl p-4 flex gap-8">
                    {/* Sidebar */}
                    <div className="h-full w-1/4 bg-white/10 rounded-xl p-2 flex flex-col min-h-0">
                        {/* Карточка пользователя — не растягивается */}
                        <div className="flex-none">
                            <UserCard
                                username="Taiidzy"
                                avatar="https://i.pinimg.com/1200x/08/2d/21/082d21840e59a77302eb88e2243d1336.jpg"
                                me={true}
                            />
                        </div>

                        {/* Список пользователей — занимает оставшуюся высоту и скроллится */}
                        <div className="flex-1 overflow-y-auto overflow-x-hidden mt-2 space-y-2 min-h-0">
                            {users.map((user) => (
                                <UserCard
                                    key={user.username}
                                    username={user.username}
                                    message={user.message}
                                    avatar={user.avatar}
                                    me={user.me}
                                    isOnline={user.isOnline}
                                    unreadCount={user.unreadCount}
                                    onClick={(username) => setUsername(username)}
                                />
                            ))}
                        </div>
                    </div>

                    <div className="h-full w-full bg-white/10 rounded-xl">
                        {/* Чат */}
                        {username && <Chat username={username} />}
                    </div>
                </div>
            </div>
        </AnimatedBackground>
    );
};

export default Home;
